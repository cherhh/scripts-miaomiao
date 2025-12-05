export GLOG_v=1

mooncake_master -port 50051 -max_threads 64 -metrics_port 9004 \
  --enable_http_metadata_server=true \
  --http_metadata_server_host=0.0.0.0 \
  --http_metadata_server_port=8080