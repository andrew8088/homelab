#!/bin/sh

op item list --vault homelab | sed '1d' | awk '{print $2}' | while read title; do
  content=$(op item get "$title" --vault homelab --format json)
  echo $content | jq -r '.tags[]' | while read namespace; do
    literals=$(echo $content | jq -r '.fields[] | select(.id!="notesPlain") | "--from-literal=\(.label)=\(.value)"')
    
    kubectl create secret generic $title \
      --namespace="$namespace" \
      $literals
  done
done
