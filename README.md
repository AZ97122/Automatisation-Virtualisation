# Projet Backup Automatisation sur cluster proxmox (Terraform et Ansible)

Automatisation d'une stratégie de sauvegarde pour cluster Proxmox Virtual Environment (PVE) avec Proxmox Backup Server (PBS), Terraform et Ansible.

---

## Objectif

Déployer **de zéro** une infrastructure de sauvegarde fonctionnelle, automatisée et testée sur un cluster Proxmox VE :

- Provisionnement de VMs applicatives via Terraform
- Configuration de Proxmox Backup Server via Ansible
- Intégration PBS ↔ PVE pour les jobs de backup automatiques
- Restauration automatisée

---

##  Fonctionnalités

| Fonctionnalité | Description |
|---|---|
| Déploiement zéro-touch | 4 VMs sur 4 nœuds Proxmox, en une commande |
| Secrets sécurisés | Tokens dynamiques + Ansible Vault (AES-256) |
| Backups planifiés | Quotidien à 1h |
| Maintenance auto | Garbage collection + Prune + Verify hebdomadaire |
| Disaster Recovery | Restorration automatisée |

---

## Machines

- Cluster Proxmox de 4 noeuds (192.168.100.241-244)
- NAS pour le stockage du cluster et les backups (192.168.100.250)
- VM de management pour le lancement d'Ansible et Terraform
- VM PBS (proxmox backup server) créée par Terraform puis configurée par Ansible
- VM web server qui sera créée par Terraform puis configurée par Ansible
- VM postgres qui sera créée par Terraform puis configurée par Ansible
- VM samba qui sera créée par Terraform puis configurée par Ansible
- 

---

## Lancement

#### Prérequis

- proxmox 9.0 +
- Ansible 2.15+ et Terraform 1.5+ sur VM de management
- Clés SSH configurées sur la VM de management vers les noeuds proxmox
- Template cloud-init d'une vm debian

### Installations et déploiement

``` bash
# Se placer dans le dossier du projet "projet-backup-automation"
# 1. Provisionner les VMs
cd terraform
terraform apply -parallelism=1

# 2. Bootstrap PVE (créatiom token pour Ansible)
cd ../Ansible
ansible-playbook playbooks/00-bootstrap-pve.yml

# 3. Déployer PBS
ansible-playbook playbooks/01-deploy-pbs.yml --ask-vault-password

# 4. Intégrer le PBS au cluster proxmox
ansible-playbook playbooks/02-integrate-pbs-pve.yml

# 5. Déployer les applications de démo sur les VMs
ansible-playbook playbooks/03-deploy-applications.yml --ask-vault-password

# Optionnel
# Test de restauration d'un backup sur une vm temporaire ID 9999 (supprimée après restoration)
ansible-playbook playbooks/04-test-restore.yml

# Restore un backup (détruit puis restaure la VM)
ansible-playbook playbooks/05-disaster-recovery.yml -e confirm_dr=YES --ask-vault-password

```

## Backups

01:00  Job PVE → Snapshot live + transfert vers PBS
- Application-consistent (fsfreeze/fsthaw)
- Compression zstd
- Déduplication chunks (PBS)

02:30  Prune-job PBS → Suppression des backups expirés (rétention)

03:00  GC PBS (dimanche) → Suppression chunks orphelins

04:00  Verify-job PBS (samedi) → Validation cryptographique des backups

## Sécurité

### Information sensibles

1. Clé SSH (seul secret manuel)  
▼
┌─────────────────────────────────────────┐
│   2. Tokens API (générés dynamiquement) │
│      • Token PVE pour Terraform         │
│      • Token PVE pour Ansible           │
│      • Token PBS pour PVE               │
└──────────────────┬──────────────────────┘
▼
┌─────────────────────────────────────────┐
│   3. Mots de passe (Ansible Vault AES)  │
│      • Root PBS                         │
│      • User backup PBS                  │
│      • PostgreSQL appuser               │
└─────────────────────────────────────────┘

### Permissions NFS

| Acteur | Rôle | Pourquoi |
|---|---|---|
| User `backup@pbs` | DatastoreAdmin | Création + suppression (prune) |
| Token API PBS | DatastoreAdmin | Idem (utilisé par PVE) |

### Permissions PVE

| Acteur | Rôle | Pourquoi |
|---|---|---|
| User `terraform@pve` | Administrator | Création VMs, gestion infra |
| User `ansible@pve` | Administrator | Jobs backup, storages |

## Flux de déploiement

terraform apply
└─► Provisionnement VMs sur Proxmox
└─► Cloud-init configure réseau, hostname, SSH
ansible-playbook 00-bootstrap-pve
└─► SSH vers HYDRA-01 (root)
└─► Création user ansible@pve
└─► Génération token API
└─► Sauvegarde dans artifacts/
ansible-playbook 01-deploy-pbs
└─► Installation PBS sur VM-PBS
└─► Montage NFS du NAS
└─► Création datastore + user + token
└─► Configuration GC, prune-job, verify-job
ansible-playbook 02-integrate-pbs-pve
└─► Lecture credentials PVE + PBS depuis artifacts/
└─► Création storage PBS dans PVE (API)
└─► Création de 3 jobs de backup (un par nœud)
ansible-playbook 03-deploy-applications
└─► Installation services métier (Nginx, PG, Samba)
└─► Données de démo
