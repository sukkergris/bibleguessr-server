# server-install-devcontainer.md

## Notes on Running server-install.sh in a Devcontainer

- The script server-install.sh is intended for real server environments with root/systemd access.
- When run in a devcontainer, you may see warnings/errors like:
  - "Failed to resolve user 'systemd-network': No such process"
  - "System has not been booted with systemd as init system (PID 1). Can't operate."
- These are expected because devcontainers do not run systemd or have all system users/groups.
- Service management commands (systemctl, service enable/start) will fail in devcontainers.
- These errors do not affect development workflows and can be ignored in containers.
- For devcontainers, use the test-install task in Taskfile.Installation.yml, which only runs safe, idempotent steps.
- Do not use server-install.sh for devcontainer setup—it's for production/VM/server bootstrapping only.

## Summary

- Ignore systemd/user warnings in containers
- Use test-install for dev workflows
- Use server-install.sh only on real servers
