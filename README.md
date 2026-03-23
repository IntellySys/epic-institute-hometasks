# EPIC Institute Hometasks

Course hometasks and supporting materials for EPIC Institute cloud and DevOps practice sessions.

## Approach

These hometasks are designed to be:
- screenshot-free
- remotely verifiable
- easy to check automatically

Students normally submit only the public IP of their EC2 instance.

Each task uses the same general pattern:
- a custom web page exposed from the instance
- a machine-readable `/check.json` endpoint
- automatic validation of the required setup

## Structure

- `HT3/`
  EC2 basics with `User data`, `nginx`, and a simple remote verification contract.
- `HT4/`
  Custom VPC networking, subnet layout validation, and IAM role update for read-only EC2 inspection.
- `HT5/`
  Dockerized `nginx` on Ubuntu, HTTPS, HTTP-to-HTTPS redirect, and container-aware validation.
