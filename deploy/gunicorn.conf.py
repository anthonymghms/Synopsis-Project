"""Small-VPS configuration; Nginx is the only public HTTP listener."""

bind = "127.0.0.1:8010"
workers = 1
worker_class = "gthread"
threads = 4
worker_connections = 64
timeout = 120
graceful_timeout = 600
keepalive = 5

# Firebase clients and the import thread pool must be initialized in the worker.
preload_app = False
# Request-count recycling could interrupt the in-process background importer.
max_requests = 0
reload = False

worker_tmp_dir = "/run/paragospels"
forwarded_allow_ips = "127.0.0.1"
accesslog = "-"
errorlog = "-"
loglevel = "info"
capture_output = True
