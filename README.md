# Projet Backup Automatisation sur cluster proxmox (Terraform et Ansible)

Automatisation d'une stratégie de sauvegarde pour cluster Proxmox Virtual Environment (PVE) avec Proxmox Backup Server (PBS), Terraform et Ansible.

Documentations spécifiques disponibles dans le dossier Documentation

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

2. Tokens API (générés dynamiquement) 
      • Token PVE pour Terraform         
      • Token PVE pour Ansible           
      • Token PBS pour PVE               


3. Mots de passe (Ansible Vault AES)  
      • Root PBS                         
      • User backup PBS                  
      • PostgreSQL appuser               


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

# Guide d'utilisation

## Workflow quotidien

### Vérifier l'état des backups

```bash
# Voir les backups récents
ssh debian@192.168.100.221 "sudo proxmox-backup-manager snapshot list main-datastore"

# Voir l'état du datastore
ssh debian@192.168.100.221 "sudo proxmox-backup-manager datastore show main-datastore"

# Via l'interface web
# https://192.168.100.221:8007 → Datastore → main-datastore → Content
```

### Lancer un backup manuel

```bash
# Via Proxmox CLI (depuis le nœud où est la VM)
ssh root@192.168.100.241 "vzdump 310 --storage pbs-main --mode snapshot --compress zstd"

# Ou via Ansible (relance le job)
ssh root@192.168.100.241 "pvesh create /nodes/HYDRA-01/vzdump --vmid 310 --storage pbs-main"
```

### Modifier la stratégie de backup

Pour changer le planning ou la rétention, éditer le playbook puis le relancer :

```bash
nano ansible/playbooks/02-integrate-pbs-pve.yml
# Modifier backup_schedule ou backup_retention

ansible-playbook playbooks/02-integrate-pbs-pve.yml
```

Le playbook supprime l'ancien job et le recrée avec la nouvelle config (déclaratif).

## Tests de restauration

### Test sur la VM par défaut (VM-WEBSERV)

```bash
ansible-playbook playbooks/04-test-restore.yml
```

### Test sur une autre VM

```bash
# VM-DBSERV
ansible-playbook playbooks/04-test-restore.yml \
  -e source_vmid=311 \
  -e source_vm_name=VM-DBSERV \
  -e source_node=HYDRA-03

# VM-FILESERV
ansible-playbook playbooks/04-test-restore.yml \
  -e source_vmid=312 \
  -e source_vm_name=VM-FILESERV \
  -e source_node=HYDRA-04
```

### Mode debug (sans cleanup)

```bash
ansible-playbook playbooks/04-test-restore.yml -e cleanup_after_test=false
```

La VM 999 est conservée pour inspection manuelle :

```bash
# Vérifier que la VM tourne
ssh root@192.168.100.241 "qm guest exec 999 -- systemctl is-active nginx"

# Console graphique
# https://192.168.100.241:8006 → VM 999 → Console

# Cleanup manuel quand fini
ssh root@192.168.100.241 "qm stop 999 && qm destroy 999 --purge --destroy-unreferenced-disks 1"
```

### Lire les rapports

```bash
# Dernier rapport
cat $(ls -t artifacts/restore-tests/*.json | head -1) | jq

# Tous les rapports
ls -lt artifacts/restore-tests/
```

## Disaster Recovery

**Cette procédure détruit la VM cible avant de la restaurer.**

```bash
# Restauration de la VM 310 depuis le dernier backup
ansible-playbook playbooks/05-disaster-recovery.yml -e confirm_dr=YES

# Pour une autre VM
ansible-playbook playbooks/05-disaster-recovery.yml \
  -e target_vmid=311 \
  -e target_vm_name=VM-DBSERV \
  -e target_node=HYDRA-03 \
  -e confirm_dr=YES
```

⏱️ ~3-5 minutes selon la taille de la VM.

## Maintenance PBS

### Lancer un Garbage Collection manuel

```bash
ssh debian@192.168.100.221 "sudo proxmox-backup-manager garbage-collection start main-datastore"
```

### Lancer un verify manuel

```bash
ssh debian@192.168.100.221 "sudo proxmox-backup-manager verify-job run verify-main-datastore"
```

### Supprimer un backup spécifique

```bash
ssh debian@192.168.100.221 "sudo proxmox-backup-manager snapshot forget main-datastore vm/310/2026-05-01T01:00:00Z"
```

## Restauration partielle (fichiers)

Pour récupérer **un seul fichier** d'un backup :

1. Aller sur l'interface PBS : https://192.168.100.221:8007
2. **Datastore → main-datastore → Content**
3. Cliquer sur le snapshot voulu
4. Onglet **File Browser**
5. Naviguer dans le filesystem de la VM
6. Télécharger le fichier individuellement

## Mises à jour du projet

```bash
# Mettre à jour le code
cd ~/projet-backup-automation
git pull

# Réappliquer la config
cd ansible
ansible-playbook playbooks/01-deploy-pbs.yml          # Si changement PBS
ansible-playbook playbooks/02-integrate-pbs-pve.yml   # Si changement jobs
ansible-playbook playbooks/03-deploy-applications.yml # Si changement apps
```

Tous les playbooks sont **idempotents** : les relancer n'a pas d'effet de bord si rien n'a changé.

## Surveillance manuelle

### Espace disque PBS

```bash
ssh debian@192.168.100.221 "df -h /mnt/pbs-datastore"
```

### Logs PBS

```bash
ssh debian@192.168.100.221 "sudo journalctl -u proxmox-backup-proxy -n 50"
```

### Logs PVE backup

```bash
ssh root@192.168.100.241 "tail -100 /var/log/vzdump-310.log"
```


