#!/bin/bash

sudo docker compose down; sudo docker volume prune -f; sudo docker compose up
