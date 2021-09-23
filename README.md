# switch_os

- tested with host `Ubuntu 18.04`, target `Ubuntu 16.04`, `Ubuntu 18.04`, `Ubuntu 20.04`, `Debian 9`, `Debian 10`, `Debian 11`
- not support `CentOS`
- cannot use `~` to replace the path in `$post_script`.

## Environment Variables

You can set the variables defined in the setting function instead of using default values, which will be displayed during execution.

## Example

```bash
netboot_url="http://archive.ubuntu.com/ubuntu/dists/focal-updates/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64" &&
    root_password="root_password" &&
    bash <(wget -qO- "http://raw.githubusercontent.com/FH0/switch_os/main/switch_os.sh")
```
