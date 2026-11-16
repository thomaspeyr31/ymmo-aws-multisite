# Estimation des coûts — Ymmo (cloud-natif AWS)

> Livrable « liste matériel & budgétisation » du sujet. **Tarifs catalogue On-Demand, région
> Paris (`eu-west-3`)**, hors transfert de données inter-zones/Internet (négligeable en démo) et
> hors taxes. Établi le **2026-06-07** à partir de l'**inventaire réellement déployé** (pas une
> estimation théorique). Conversion indicative **1 $ ≈ 0,92 €**.

## 1. Inventaire déployé (source : `aws ec2 describe-*`)

| # | Ressource | Qté | Détail |
|---|-----------|-----|--------|
| 1 | EC2 Windows t3.medium | 2 | `ec2-dc-siege`, `ec2-admin-siege` |
| 2 | EC2 Windows t3.large | 3 | `ec2-poste-marseille`, `ec2-poste-nimes`, `ec2-fileserver-siege` (FILESRV) |
| 3 | EC2 Linux t3.medium | 1 | `ec2-vpn-gateway-siege` (passerelle IPSec) |
| 4 | NAT Gateway | 3 | 1 par VPC (siège + 2 agences) |
| 5 | Transit Gateway — attachments | 3 | 1 par VPC |
| 6 | IPv4 publiques (EIP) | 4 | 3 EIP NAT + 1 EIP VPN |
| 7 | Volumes EBS | 166 Go | 5×30 Go (Windows) + 2×8 Go (Linux) — gp2/gp3 |
| 8 | AWS Network Firewall (step 05) | 1 endpoint | *écrit (`firewall.tf`), pas encore appliqué* |

## 2. Tarifs unitaires retenus (eu-west-3, On-Demand)

| Ressource | Tarif |
|-----------|-------|
| t3.medium **Windows** | 0,0942 $/h |
| t3.large **Windows** | 0,1884 $/h |
| t3.medium **Linux** | 0,0470 $/h |
| NAT Gateway | 0,048 $/h (+ 0,048 $/Go traité) |
| TGW attachment | 0,05 $/h (+ 0,02 $/Go) |
| IPv4 publique | 0,005 $/h |
| EBS gp2 / gp3 | 0,116 / 0,0928 $/Go·mois |
| Network Firewall — endpoint | 0,395 $/h (+ 0,065 $/Go) |

## 3. Coût journalier détaillé

| # | Poste | Calcul | **$/jour** | €/jour |
|---|-------|--------|-----------:|-------:|
| 1 | DC (t3.medium Win) | 0,0942×24 | 2,26 | 2,08 |
| 2 | Admin (t3.medium Win) | 0,0942×24 | 2,26 | 2,08 |
| 3 | Poste Marseille (t3.large Win) | 0,1884×24 | 4,52 | 4,16 |
| 4 | Poste Nîmes (t3.large Win) | 0,1884×24 | 4,52 | 4,16 |
| 5 | FILESRV (t3.large Win) | 0,1884×24 | 4,52 | 4,16 |
| 6 | Passerelle VPN (t3.medium Linux) | 0,0470×24 | 1,13 | 1,04 |
| 7 | NAT Gateway ×3 | 3×0,048×24 | 3,46 | 3,18 |
| 8 | TGW attachments ×3 | 3×0,05×24 | 3,60 | 3,31 |
| 9 | IPv4 publiques ×4 | 4×0,005×24 | 0,48 | 0,44 |
| 10 | EBS (166 Go) | — | 0,64 | 0,59 |
| | **Sous-total (infra actuelle)** | | **≈ 27,4** | **≈ 25,2** |
| 11 | Network Firewall (1 endpoint) | 0,395×24 | 9,48 | 8,72 |
| | **Total AVEC pare-feu** | | **≈ 36,9** | **≈ 33,9** |

## 4. Synthèse

| Scénario | $/jour | €/jour | $/mois (~30 j) | €/mois |
|----------|-------:|-------:|---------------:|-------:|
| Infra actuelle (sans pare-feu) | ~27 | ~25 | ~822 | ~756 |
| Avec AWS Network Firewall | ~37 | ~34 | ~1 107 | ~1 018 |

## 5. Leviers d'optimisation (par impact décroissant)

1. **EC2 Windows (#1–#5)** = ~73 % du coût compute. Éteindre les instances hors démo : on ne paie
   plus que l'EBS (~0,64 $/j) → **gros gain**. (Licences Windows incluses = ~50 % du prix d'une
   instance Windows ; un poste Linux serait ~2× moins cher mais le sujet impose Windows/AD.)
2. **AWS Network Firewall (#11)** = ~9,5 $/j à lui seul, **facturé à l'heure même sans trafic** →
   à **détruire après la démo**.
3. **NAT (#7) + TGW (#8)** = ~7 $/j fixes tant que ça tourne → détruits par `terraform destroy`.

## 6. Modèle « éphémère » (recommandé)

L'infra est conçue pour être **jetable** : `terraform apply` le matin, `terraform destroy` le soir.

- Détruit (NAT, TGW, Firewall, IPv4, EC2) → coût ramené **quasi à 0**.
- Seul l'**EBS persiste** s'il n'est pas détruit (~0,64 $/j) ; le `destroy` complet l'enlève aussi.
- Une **journée de démo complète** (infra montée + pare-feu) ≈ **1 à 2 $** si montée/détruite dans la journée.

## 7. Limites & mise à jour

- **Tarifs catalogue** : un compte avec remises (Savings Plans, EDP) paierait moins.
- **Exclus** : transfert de données (NAT/TGW/Firewall par Go), CloudWatch Logs, taxes — négligeables
  en démo, à intégrer pour une estimation de production.
- **Rafraîchissement automatisé** possible via **Infracost** (`infracost breakdown --path
  infra/terraform/environments/demo`) — nécessite une clé API gratuite (`infracost auth login`).
  Cette estimation manuelle sert de référence et de garde-fou.
