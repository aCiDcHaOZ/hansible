---
- name: Verwijder WordPress CT op Proxmox
  hosts: localhost
  gather_facts: false
  collections:
    - community.proxmox

  vars:
    proxmox_api_host: "10.24.43.2"
    proxmox_api_port: 8006
    proxmox_node: "linda"
    proxmox_api_user: "root@pam"
    proxmox_api_password: "{{ lookup('ansible.builtin.file', 'pwd_secret') | trim }}"

    local_home: "{{ lookup('ansible.builtin.env', 'HOME') }}"

  pre_tasks:
    - name: Controleer dat klantnummer is opgegeven
      ansible.builtin.assert:
        that:
          - klantnummer is defined
          - klantnummer | string | length > 0
        fail_msg: "Geef een klantnummer op via -e klantnummer=123"

    - name: Stel hostname, VMID en keypaden vast
      ansible.builtin.set_fact:
        ct_hostname: "wordpress-{{ klantnummer }}"
        ct_vmid: "{{ klantnummer | int }}"
        ct_ssh_key_path: "{{ local_home }}/keys/id_ed25519_{{ klantnummer }}"

    - name: Lees CT-config uit Proxmox
      ansible.builtin.shell: >
        ssh -o StrictHostKeyChecking=no root@{{ proxmox_api_host }}
        "pct config {{ ct_vmid }}"
      args:
        executable: /bin/bash
      register: ct_config_result
      changed_when: false
      failed_when: false

    - name: Bepaal of de CT bestaat
      ansible.builtin.set_fact:
        ct_exists: "{{ ct_config_result.rc == 0 }}"

    - name: Haal net0-config uit CT-config
      ansible.builtin.set_fact:
        ct_net0_line: >-
          {{
            (ct_config_result.stdout_lines | default([])
            | select('match', '^net0:')
            | list
            | first
            | default(''))
          }}
      when: ct_exists

    - name: Haal IP-adres uit net0-config
      ansible.builtin.set_fact:
        ct_ip_address: "{{ ct_net0_line | regex_search('ip=([0-9.]+)/(\\d+)', '\\1') | first }}"
      when:
        - ct_exists
        - ct_net0_line | length > 0
        - ct_net0_line is search('ip=[0-9.]+/[0-9]+')

  tasks:
    - block:
        - name: Stop de CT
          community.proxmox.proxmox:
            api_host: "{{ proxmox_api_host }}"
            api_port: "{{ proxmox_api_port }}"
            api_user: "{{ proxmox_api_user }}"
            api_password: "{{ proxmox_api_password }}"
            validate_certs: false
            node: "{{ proxmox_node }}"
            vmid: "{{ ct_vmid }}"
            state: stopped
          when: ct_exists
          ignore_errors: true
          no_log: true

        - name: Verwijder de CT
          community.proxmox.proxmox:
            api_host: "{{ proxmox_api_host }}"
            api_port: "{{ proxmox_api_port }}"
            api_user: "{{ proxmox_api_user }}"
            api_password: "{{ proxmox_api_password }}"
            validate_certs: false
            node: "{{ proxmox_node }}"
            vmid: "{{ ct_vmid }}"
            state: absent
          when: ct_exists
          no_log: true

        - name: Verwijder lokale private key
          ansible.builtin.file:
            path: "{{ ct_ssh_key_path }}"
            state: absent

        - name: Verwijder lokale public key
          ansible.builtin.file:
            path: "{{ ct_ssh_key_path }}.pub"
            state: absent

        - name: Geef IP-adres terug aan ip_manager
          ansible.builtin.command: "./ip_manager.sh remove {{ ct_ip_address }}"
          args:
            chdir: "{{ playbook_dir }}"
          when: ct_ip_address is defined
          register: ip_remove_result
          changed_when: ip_remove_result.rc == 0

      rescue:
        - name: Meld teardown failure
          ansible.builtin.fail:
            msg: >-
              Verwijderen van CT {{ ct_hostname }} is mislukt.
              Controleer handmatig of de CT, keys en het IP-adres zijn opgeruimd.

    - name: Toon resultaat CT
      ansible.builtin.debug:
        msg: >-
          {% if ct_exists %}
          CT {{ ct_hostname }} (VMID {{ ct_vmid }}) is verwijderd.
          {% else %}
          CT {{ ct_hostname }} (VMID {{ ct_vmid }}) bestond niet meer.
          {% endif %}

    - name: Toon resultaat keys
      ansible.builtin.debug:
        msg: "Lokale keys verwijderd: {{ ct_ssh_key_path }} en {{ ct_ssh_key_path }}.pub"

    - name: Toon resultaat IP-release
      ansible.builtin.debug:
        msg: >-
          {% if ct_ip_address is defined %}
          IP-adres {{ ct_ip_address }} is teruggegeven aan ip_manager.
          {% else %}
          Er is geen IP-adres uit de CT-config gehaald, dus er is niets teruggegeven aan ip_manager.
          {% endif %}
