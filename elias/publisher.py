"""Publishing through Meta's official Instagram Content Publishing API.

Flow (per Meta docs): create a media container -> wait until status_code is FINISHED ->
POST media_publish. Media must be reachable at a public https URL. Requires an Instagram
professional (Business/Creator) account and an access token with content-publish permission.

Safety: dry-run by default; --live publishes only items that a human approved and that
have not changed since approval. No scraping, no private endpoints, no credential handling
beyond reading the token you put in the environment."""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

from elias import queue, store


class PublishError(Exception):
    pass


class GraphClient:
    def __init__(self, host, version, token, user_id, opener=None, sleep=time.sleep):
        self.base = f"{host.rstrip('/')}/{version}"
        self.token = token
        self.user_id = user_id
        self.opener = opener or urllib.request.urlopen
        self.sleep = sleep

    @classmethod
    def from_settings(cls, settings=None, **kw):
        g = (settings or store.settings())["graph_api"]
        token, user_id = os.environ.get(g["access_token_env"]), os.environ.get(g["ig_user_id_env"])
        if not token or not user_id:
            raise PublishError(f"set {g['access_token_env']} and {g['ig_user_id_env']} in the environment")
        return cls(g["host"], g["version"], token, user_id, **kw)

    def _call(self, method, path, params):
        params = {k: v for k, v in params.items() if v is not None}
        params["access_token"] = self.token
        data = urllib.parse.urlencode(params)
        url = f"{self.base}/{path}"
        if method == "GET":
            req = urllib.request.Request(f"{url}?{data}")
        else:
            req = urllib.request.Request(url, data=data.encode(), method="POST")
        try:
            with self.opener(req) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            raise PublishError(f"{method} {path}: HTTP {e.code} {e.read().decode(errors='replace')}") from e

    def create_container(self, **params):
        return self._call("POST", f"{self.user_id}/media", params)["id"]

    def wait_ready(self, container_id, timeout_s=300, every_s=5):
        waited = 0
        while True:
            status = self._call("GET", container_id, {"fields": "status_code"}).get("status_code")
            if status in (None, "FINISHED", "PUBLISHED"):
                return
            if status in ("ERROR", "EXPIRED"):
                raise PublishError(f"container {container_id} {status}")
            if waited >= timeout_s:
                raise PublishError(f"container {container_id} still {status} after {timeout_s}s")
            self.sleep(every_s)
            waited += every_s

    def publish(self, container_id):
        return self._call("POST", f"{self.user_id}/media_publish", {"creation_id": container_id})["id"]

    def permalink(self, media_id):
        return self._call("GET", media_id, {"fields": "permalink"}).get("permalink")

    def insights(self, media_id, metrics):
        return self._call("GET", f"{media_id}/insights", {"metric": ",".join(metrics)})


def _is_video(url_or_name):
    return url_or_name.lower().rsplit(".", 1)[-1] in ("mp4", "mov")


def plan_calls(item):
    """The exact container calls for an item, without sending anything (used by dry-run and live)."""
    caption = queue.full_caption(item)
    mt, assets = item["media_type"], item["assets"]
    if mt == "IMAGE":
        return [{"step": "container", "params": {"image_url": assets[0]["public_url"], "caption": caption}}]
    if mt == "REELS":
        return [{"step": "container", "params": {"media_type": "REELS", "video_url": assets[0]["public_url"],
                                                 "caption": caption, "share_to_feed": "true"}}]
    if mt == "STORIES":
        key = "video_url" if _is_video(assets[0]["name"]) else "image_url"
        return [{"step": "container", "params": {"media_type": "STORIES", key: assets[0]["public_url"]}}]
    if mt == "CAROUSEL":
        calls = []
        for a in assets:
            p = {"is_carousel_item": "true"}
            if _is_video(a["name"]):
                p.update(media_type="VIDEO", video_url=a["public_url"])
            else:
                p["image_url"] = a["public_url"]
            calls.append({"step": "child", "params": p})
        calls.append({"step": "container", "params": {"media_type": "CAROUSEL", "caption": caption}})
        return calls
    raise PublishError(f"unsupported media_type {mt}")


def check_publishable(item, now=None, ignore_schedule=False):
    if item["status"] == "published":
        raise PublishError(f"{item['id']} already published")
    if not queue.approval_valid(item):
        raise PublishError(f"{item['id']} has no valid human approval (status {item['status']})")
    if not ignore_schedule:
        now = now or datetime.now()
        if datetime.fromisoformat(item["scheduled_for"]) > now:
            raise PublishError(f"{item['id']} is scheduled for {item['scheduled_for']}")


def publish(item_id, live=False, client=None, ignore_schedule=False, now=None):
    item = queue.get(item_id)
    check_publishable(item, now=now, ignore_schedule=ignore_schedule)
    calls = plan_calls(item)
    if not live:
        return {"dry_run": True, "id": item_id, "calls": calls}
    client = client or GraphClient.from_settings()
    children = []
    container = None
    for c in calls:
        if c["step"] == "child":
            cid = client.create_container(**c["params"])
            client.wait_ready(cid)
            children.append(cid)
        else:
            params = dict(c["params"])
            if children:
                params["children"] = ",".join(children)
            container = client.create_container(**params)
            client.wait_ready(container)
    media_id = client.publish(container)
    link = client.permalink(media_id)
    queue.mark_published(item_id, media_id, link)
    return {"dry_run": False, "id": item_id, "media_id": media_id, "permalink": link}


def due(now=None):
    now = now or datetime.now()
    return [it for it in queue.items("approved")
            if datetime.fromisoformat(it["scheduled_for"]) <= now and queue.approval_valid(it)]
