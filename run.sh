#!/bin/bash
cd /home/apoorv/hosted/ ; docker compose down ; docker compose build ; docker compose up -d
