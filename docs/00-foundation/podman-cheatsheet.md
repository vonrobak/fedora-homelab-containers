# Podman Cheatsheet

```bash
podman info
podman images
podman ps -a
podman run -it --rm alpine sh
podman run -d -p 8080:80 --name web nginx
podman logs -f web
podman exec -it web sh
podman stop web && podman rm web
podman inspect web | jq '.[0].NetworkSettings'
podman network ls
podman network create internal-net
podman run --network internal-net --name a -d nginx
podman run --network internal-net --rm -it curlimages/curl curl http://a
podman generate systemd --name web --files --new
```
Security flags to standardize on:
- `--cap-drop=ALL`
- `--read-only`
- `--userns=keep-id`
- `-v /path:/path:Z`
