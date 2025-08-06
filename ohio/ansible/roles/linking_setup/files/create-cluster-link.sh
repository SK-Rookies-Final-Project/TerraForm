#!/bin/bash

# Kafka Cluster Link 생성 스크립트 (브로커 1번)
/bin/kafka-cluster-links \
  --bootstrap-server ec2-3-35-199-84.ap-northeast-2.compute.amazonaws.com:29092 \
  --create \
  --link link-link \
  --config-file /engn/confluent/link-link.config