# az-infra-mgmt

``` bash
base64data=$(cat base64.txt)
{
  echo "-----BEGIN CERTIFICATE-----"
  echo "$base64data"
  echo "-----END CERTIFICATE-----"
} > mycert.crt
```
``` yaml
---
- name: Backup existing certificate-related files
  hosts: localhost
  vars:
    cert_dir: "/path/to/your/cert/folder"  # <-- update this
    backup_dir: "{{ cert_dir }}/backup_{{ lookup('pipe', 'date +%Y%m%d_%H%M%S') }}"
    extensions:
      - "*.crt"
      - "*.pem"
      - "*.p12"

  tasks:
    - name: Create backup directory
      file:
        path: "{{ backup_dir }}"
        state: directory
        mode: '0755'

    - name: Find files to back up
      find:
        paths: "{{ cert_dir }}"
        patterns: "{{ extensions }}"
        recurse: no
      register: cert_files

    - name: Copy files to backup directory
      copy:
        src: "{{ item.path }}"
        dest: "{{ backup_dir }}/"
        mode: preserve
      loop: "{{ cert_files.files }}"

```
