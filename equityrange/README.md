version: "3.8"

# equityrange.com root site — static HTML served by shared proxy nginx.
# No app container needed; nginx serves files directly from a volume mount.
#
# The proxy's docker-compose.yml mounts ./equityrange-html:/var/www/equityrange
# so this directory just holds the static files — no separate container required.
#
# If you later need a backend (Node/Express), add an app service here
# and swap the nginx conf to proxy_pass instead of root/try_files.

# Nothing to run — static files are served directly by proxy-nginx.
# This file is here as a placeholder if you want to add a backend later.
