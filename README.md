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
---
---
- name: Retrieve Venafi Certificate in Base64 and Convert to .crt
  hosts: your_target_hosts  # Replace with your target host group or hostname
  vars:
    venafi_url: "your_venafi_url"  # Replace with your Venafi platform URL
    venafi_zone: "your\\venafi\\application\\zone"  # Replace with your Venafi certificate zone
    venafi_friendly_name: "your_certificate_friendly_name"  # Replace with the certificate's friendly name in Venafi
    venafi_api_key: "your_venafi_api_key"  # Replace with your Venafi API key (securely manage this)
    local_destination_path: "/path/to/your/destination/folder"  # Replace with the desired local folder
    crt_filename: "{{ venafi_friendly_name }}.crt"
    crt_fullpath: "{{ local_destination_path }}/{{ crt_filename }}"

  tasks:
    - name: Check if the CRT certificate file already exists
      stat:
        path: "{{ crt_fullpath }}"
      register: crt_file_check

    - name: Retrieve certificate from Venafi in Base64 format
      when: not crt_file_check.stat.exists
      uri:
        url: "{{ venafi_url }}/vedsdk/Certificates/Retrieve"
        method: POST
        headers:
          Content-Type: "application/json"
          Authorization: "Bearer {{ venafi_api_key }}"
        body_format: json
        body: >-
          {
            "Zone": "{{ venafi_zone }}",
            "FriendlyName": "{{ venafi_friendly_name }}",
            "Format": "Base64"
          }
        return_content: yes
        status_code: [200]
      register: venafi_certificate_retrieval
      no_log: yes  # Sensitive information, avoid logging

    - name: Create destination directory if it doesn't exist
      when: not crt_file_check.stat.exists
      file:
        path: "{{ local_destination_path }}"
        state: directory
        mode: '0755'

    - name: Save the Base64 encoded certificate to a temporary .cer file
      when: not crt_file_check.stat.exists and venafi_certificate_retrieval.content is defined
      copy:
        content: "{{ venafi_certificate_retrieval.content }}"
        dest: "{{ local_destination_path }}/{{ venafi_friendly_name }}.cer"
        mode: '0644'
      no_log: yes # Contains certificate data

    - name: Convert the .cer file to .crt format
      when: not crt_file_check.stat.exists and venafi_certificate_retrieval.content is defined
      shell: |
        openssl x509 -inform der -in "{{ local_destination_path }}/{{ venafi_friendly_name }}.cer" -outform pem -out "{{ crt_fullpath }}"
      args:
        creates: "{{ crt_fullpath }}"
      become: yes # May require elevated privileges depending on the destination path

    - name: Remove the temporary .cer file
      when: not crt_file_check.stat.exists and venafi_certificate_retrieval.content is defined
      file:
        path: "{{ local_destination_path }}/{{ venafi_friendly_name }}.cer"
        state: absent
      become: yes # May require elevated privileges

    - name: Inform user that the CRT certificate already exists
      when: crt_file_check.stat.exists
      debug:
        msg: "Certificate '{{ crt_filename }}' already exists at '{{ crt_fullpath }}'."

    - name: Inform user about successful certificate retrieval and conversion
      when: not crt_file_check.stat.exists and venafi_certificate_retrieval.content is defined
      debug:
        msg: "Successfully retrieved certificate from Venafi and saved as '{{ crt_filename }}' at '{{ crt_fullpath }}'."

    - name: Inform user about failed certificate retrieval
      when: not crt_file_check.stat.exists and venafi_certificate_retrieval.failed
      debug:
        msg: "Failed to retrieve certificate '{{ venafi_friendly_name }}' from Venafi. Error: {{ venafi_certificate_retrieval.msg }}"
```
