# Guide d'installation

Ce document détaille l'installation **pas à pas** du projet sur un cluster Proxmox VE existant.

## Prérequis

### Infrastructure

- Cluster **Proxmox VE 9.x** avec au moins 4 nœuds
- **NAS** avec partage NFS configuré
- **Réseau** avec accès entre tous les composants

### Sur le NAS

Configurer un partage NFS avec :
- **NFSv3** (NFSv4 problématique sur certains NAS comme UGreen)
- **Squash** : "No mapping" (équivalent `no_root_squash`)
- **Capacité** : minimum 100 Go (recommandé 1 To+)

### Sur le cluster Proxmox

1. Cluster monté et fonctionnel
2. Storage partagé `VMs-Disks` configuré (NFS sur le NAS)
3. **Template cloud-init Debian 12** créé avec ID 9001 sur HYDRA-01
   - Voir [docs/template-creation.md](template-creation.md)

### Sur le control node (VM-MGMT)

```bash
# Installation des outils
sudo apt update
sudo apt install -y git curl wget gnupg lsb-release

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Ansible (via pip pour avoir une version récente)
sudo apt install -y python3-pip
pip install --break-system-packages ansible

# Collections Ansible
ansible-galaxy collection install community.general community.postgresql ansible.posix
```

## Étape 1 — Cloner le projet

```bash
cd ~
git clone https://github.com/<your-username>/projet-backup-automation.git
cd projet-backup-automation
```

## Étape 2 — Configurer Terraform

### Créer `terraform.tfvars`

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # Si fourni
nano terraform.tfvars
```

Contenu minimum :

```hcl
proxmox_endpoint         = "https://192.168.100.241:8006"
proxmox_api_token_id     = "terraform@pve!tf-token"
proxmox_api_token_secret = "VOTRE-SECRET-ICI"
ssh_public_key           = "ssh-ed25519 AAAA... your-key"
storage_id               = "VMs-Disks"
template_id              = 9001
```

### Créer le token Proxmox initial

Sur HYDRA-01 :

```bash
ssh root@192.168.100.241
pveum user add terraform@pve
pveum aclmod / --users terraform@pve --roles Administrator
pveum user token add terraform@pve tf-token --privsep=0
# Note bien la valeur retournée → secret du token
```

## Étape 3 — Configurer le NAS

### Créer le partage NFS

Sur le NAS :
1. Créer un dossier partagé `pbs-datastore`
2. Activer NFS (NFSv3 uniquement)
3. Configurer les permissions :
   - **Squash** : "No mapping"
   - **Read/Write** depuis le subnet 192.168.100.0/24

### Désactiver la corbeille (recommandé)

Sur les NAS UGreen, Synology, QNAP : désactiver la **corbeille réseau** sur le partage `pbs-datastore` pour éviter qu'elle se recrée automatiquement.

## Étape 4 — Configurer le vault Ansible

```bash
cd ../ansible

# Créer le mot de passe vault
echo "VotreMotDePasseFort" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Créer le fichier secrets
ansible-vault create vault/secrets.yml
```

Contenu :

```yaml
---
vault_pbs_admin_password: "MotDePasseAdminPBS"
vault_pbs_backup_password: "MotDePasseBackupPBS"
vault_pbs_root_password: "MotDePasseRoot"
vault_db_app_password: "MotDePasseDB"
```

## Étape 5 — Configurer SSH

```bash
# Générer une clé SSH si vous n'en avez pas
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copier la clé sur tous les nœuds Proxmox
for ip in 192.168.100.241 192.168.100.242 192.168.100.243 192.168.100.244; do
  ssh-copy-id root@$ip
done

# Vérifier que ça marche
ssh root@192.168.100.241 "hostname"
```

## Étape 6 — Déploiement complet

### 6.1 Provisionnement Terraform

```bash
cd ../terraform
terraform init
terraform apply -parallelism=1
```

⏱️ ~5-7 minutes (creation des 4 VMs séquentielle pour éviter les locks NFS).

### 6.2 Bootstrap PVE

```bash
cd ../ansible
ansible-playbook playbooks/00-bootstrap-pve.yml
```

⏱️ ~10 secondes.

### 6.3 Déploiement PBS

```bash
ansible-playbook playbooks/01-deploy-pbs.yml --ask-vault-password
```

⏱️ ~3-5 minutes.

### 6.4 Intégration PBS-PVE

```bash
ansible-playbook playbooks/02-integrate-pbs-pve.yml
```

⏱️ ~30 secondes.

### 6.5 Déploiement applications

```bash
ansible-playbook playbooks/03-deploy-applications.yml --ask-vault-password
```

⏱️ ~3-5 minutes.

## Étape 7 — Validation

### Vérifier les services

```bash
# Site web
curl http://192.168.100.222

# BDD
ssh debian@192.168.100.223 "sudo -u postgres psql -d demo_backup -c 'SELECT * FROM visitors;'"

# Samba
smbclient -L //192.168.100.224 -N
```

### Vérifier les jobs PBS

```bash
ssh debian@192.168.100.221 "sudo proxmox-backup-manager prune-job list"
ssh debian@192.168.100.221 "sudo proxmox-backup-manager verify-job list"
```

### Vérifier les jobs PVE

```bash
ssh root@192.168.100.241 "cat /etc/pve/jobs.cfg"
```

### Lancer un backup test

```bash
ssh root@192.168.100.241 "vzdump 310 --storage pbs-main --mode snapshot"
```

## Étape 8 — Lancer un test de restauration

```bash
ansible-playbook playbooks/04-test-restore.yml
```

⏱️ ~3-5 minutes. Le rapport JSON est généré dans `artifacts/restore-tests/`.

## Désinstallation

```bash
# Supprimer les VMs
cd terraform
terraform destroy -parallelism=1

# Note : le datastore PBS sur le NAS reste tel quel
# Pour le supprimer manuellement, accéder au NAS et supprimer le dossier
```
