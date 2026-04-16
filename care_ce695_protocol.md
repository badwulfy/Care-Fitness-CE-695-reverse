# Care Fitness CE-695 — Protocole BLE (Reverse Engineering)

## Informations Appareil

| Propriété | Valeur |
|-----------|--------|
| Nom BLE | `CARE11214031` |
| Service UART | `0000fff0-0000-1000-8000-00805f9b34fb` |
| Char R/W/Notify | `0000fff1-0000-1000-8000-00805f9b34fb` |
| Char Write-only | `0000fff2-0000-1000-8000-00805f9b34fb` |
| Service Batterie | `0000180f-0000-1000-8000-00805f9b34fb` (char `2a19`) |

---

## Encodage

**Toutes les valeurs de télémétrie sont en BCD (Binary Coded Decimal)**, sauf la fréquence cardiaque qui est en décimal classique.

```
BCD : octet 0x48 → high_nibble=4, low_nibble=8 → valeur = 48
Décimal : octet 0x5A → valeur = 90
```

---

## 1. Commande de Résistance (App → Machine)

**Header : `0x20`** — Envoyée toutes les ~1 seconde (sert aussi de keep-alive).

```
Byte:   0     1     2      3     4
      [0x20] [0x01] [LVL] [0x00] [CHK]
```

| Byte | Valeur | Description |
|------|--------|-------------|
| 0 | `0x20` | Header |
| 1 | `0x01` | Sous-commande : résistance |
| 2 | `0x01`–`0x20` | Niveau de résistance (1–32) |
| 3 | `0x00` | Padding |
| 4 | checksum | `sum(bytes[0:4]) & 0xFF` |

### Exemples confirmés (btsnoop Kinomap)

| Niveau | Trame |
|--------|-------|
| 1 | `20 01 01 00 22` |
| 11 | `20 01 0B 00 2C` |
| 12 | `20 01 0C 00 2D` |
| 15 | `20 01 0F 00 30` |
| 20 | `20 01 14 00 35` |
| 25 | `20 01 19 00 3A` |
| 32 | `20 01 20 00 41` |

> **Note** : Si on arrête d'envoyer cette commande, la machine se déconnecte après quelques secondes.

---

## 2. Télémétrie (Machine → App)

**Header : `0x20`** — Trame de **12 octets**, envoyée ~2× par seconde (alternance Page A / Page B).

```
Byte:  0     1     2     3     4     5     6     7     8     9    10    11
     [0x20] [PAGE] [HI3] [LO3] [HI5] [LO5] [HI7] [LO7] [HR]  [B9] [WAT] [CHK]
```

### Carte complète des octets

| Byte | Contenu | Encodage | Statut |
|------|---------|----------|--------|
| 0 | Header (`0x20`) | fixe | ✅ Confirmé |
| 1 | Type de page : `0x00`=A, `0x10`=B | fixe | ✅ Confirmé |
| 2 | Centaines de byte 3 | BCD | ✅ Confirmé |
| 3 | **Page A : Vitesse × 10** / **Page B : RPM** | BCD | ✅ Confirmé |
| 4 | Centaines de byte 5 | BCD | ✅ Confirmé |
| 5 | **Distance** (cumulatif) | BCD | ✅ Confirmé |
| 6 | Centaines de byte 7 | BCD | ✅ Confirmé |
| 7 | **Calories** (cumulatif) | BCD | ✅ Confirmé |
| 8 | **Fréquence cardiaque** (bpm) | **Décimal** | ✅ Confirmé |
| 9 | **Centaines de Watts** | BCD | ✅ Confirmé |
| 10 | **Unités/Dizaines de Watts** | BCD | ✅ Confirmé |
| 11 | Checksum | `sum(bytes[0:10]) & 0xFF` | ✅ Confirmé |


### Pages

- **Page A** (`data[1] == 0x00`) : byte 3 = vitesse en 0.1 km/h (BCD). Ex: `0x48` → 48 → **4.8 km/h**
- **Page B** (`data[1] == 0x10`) : byte 3 = cadence en RPM (BCD). Ex: `0x50` → **50 RPM**

### Valeurs multi-octets (>99)

Les bytes pairs (2, 4, 6) sont les **centaines** de leurs voisins impairs (3, 5, 7) :

```
Valeur = BCD(byte_pair) × 100 + BCD(byte_impair)
```

Exemple : 150 calories → byte 6 = `0x01`, byte 7 = `0x50`

### Exemples vérifiés sur la machine

| Pédalage | B3 (hex) | Vitesse | B3 (hex) | RPM | Watts | HR |
|----------|----------|---------|----------|-----|-------|-----|
| ~50 RPM | `0x48` | 4.8 km/h | `0x50` | 50 | 15 | — |
| ~60 RPM | `0x57` | 5.7 km/h | `0x60` | 60 | 20 | 90 |
| ~75 RPM | `0x74` | 7.4 km/h | `0x77` | 77 | 28 | — |
| Arrêt | `0x00` | 0.0 km/h | `0x00` | 0 | 0 | — |

---

## 3. Handshake / Init (App → Machine)

**Header : `0x40`** — Envoyée au démarrage de la connexion (4× dans le btsnoop Kinomap). Ces valeurs sont des **constantes** et ne dépendent pas du profil utilisateur (poids/taille/âge).

### Commande init (App → Machine)

```
40 00 16 0A 60
```

| Byte | Valeur | Description |
|------|--------|-------------|
| 0 | `0x40` | Header config |
| 1 | `0x00` | Sous-commande : Identification app |
| 2 | `0x16` (22) | **ID Application** (Constante) |
| 3 | `0x0A` (10) | **Version Protocole** (Constante) |
| 4 | `0x60` | Checksum (`0x40+0x00+0x16+0x0A = 0x60`) ✅ |

### Réponse init (Machine → App)

```
40 04 8C 20 01 01 01 01 F4
```

| Byte | Valeur | Description |
|------|--------|-------------|
| 0 | `0x40` | Header config |
| 1 | `0x04` | Sous-commande : Identité machine |
| 2 | `0x8C` (140) | **Modèle/Firmware ID** (Constante) |
| 3 | `0x20` (32) | **Capacité** : 32 niveaux de résistance max |
| 4-7 | `0x01` ×4 | Flags de capacités matérielles |
| 8 | `0xF4` (244) | Checksum ✅ (`sum(bytes[0:8]) & 0xFF`) |

---

## 4. Corrélation Pente (Incline) / Résistance

L'application Kinomap simule une pente virtuelle (0 % à 15 %) en envoyant des niveaux de résistance physiques (12 à 32).

**Formule observée :** `Niveau = round(12 + (Pente * 20 / 15))`

| Pente | Niveau Machine |
|:---:|:---:|
| 0 % | **12** (Plat) |
| 7.5% | **22** |
| 15 % | **32** (Max) |

---

## 5. TODO — Questions en suspens

- [ ] **Unité de Distance** : Préciser si l'incrément est en décamètres ou hectomètres.
- [ ] **Char 0xFFF2** : Caractéristique présente mais jamais sollicitée par l'application officielle (usage constructeur probable).

