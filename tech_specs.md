# Spécifications Techniques : Care Fitness Trainer

## Introduction & Contexte (Demande Initiale)
*Objectif décrit par l'utilisateur :*
« Développer une application, de A à Z, en un coup, permettant d'interagir avec mon vélo elliptique (Care Fitness CE-695) pour faire mes exercices suite au reverse engineering de son protocole Bluetooth. L'application se connectera à Apple Health pour obtenir mes pulsations cardiaques et pour stocker les données de mes exercices. Si jamais l'Apple Watch n'est pas possible, elle utilisera les données cardiaques du vélo elliptique (en cas de doublon, on privilégie l'Apple Watch). Les données santé seront stockées dans Apple Health et un historique local complètera cela sur l'application.* 
*L'app permettra de configurer l'exercice avant de démarrer selon une cible de durée/km/libre. On aura le choix entre un mode libre ou parmi au moins 8 types de séries communément utilisées où l'intensité variera au cours du temps (plat, pente, V-shape, alternance bas et haut, etc.). Si une cible de temps est choisie, la durée du motif sera adaptée (dilatée).*
*Appareils cibles : iPhone, Mac, iPad. Mode très sombre et un UI/UX orienté dashboard premium avec de gros boutons (+ / -) durant l'exercice.* »

---

Application SwiftUI permettant de contrôler et d'interagir nativement avec le vélo elliptique via Bluetooth Low Energy (BLE). L'application gère des séries d'entraînements, la télémétrie en temps réel et l'export des données santé.

## 1. Vue d'Ensemble & Plateformes
- **Plateformes cibles** : iOS (iPhone), iPadOS, et macOS (via Mac Catalyst / Designed for iPad).
- **Priorité Santé** : Intégration de **HealthKit** (iOS uniquement).
- **Apple Watch** : Utilisation native via `HKWorkoutSession` lancé sur l'iPhone. Ceci active le mode Entraînement de l'Apple Watch connectée, récupérant la fréquence cardiaque très précise en mode "passif" sans nécessiter le développement et la maintenance d'une application watchOS dédiée. Idéal pour ce projet.
- **Cas d'usage** : Visualisation en plein effort des données, changement de pentes facilité, et suivi de patterns d'efforts complexes.

---

## 2. UI / UX Design
Le design sera orienté "Dashboard Sportif Premium", spécifiquement conçu pour l'effort physique.

### Thème global 
- **Mode Sombre imposé** (`.preferredColorScheme(.dark)`), avec des tons profonds (Noir pur expérimental / Gris bleuté profond) pour maximiser le contraste et mettre en valeur les données dynamiques au néon.

### Écran Principal (En Exercice)
- **Top Bar (Minimaliste)** : Statut de connexion Bluetooth, état de la batterie, heure actuelle et Bouton Quitter/Réglages.
- **Panneau Central (Graphes avec Swift Charts)** :
  - *Arrière-plan (Prévisions des Pentes)* : Un graphique de forme type `BarChart` illustrant le *"profil"* de la série d'entraînement (les futures pentes à franchir).
  - *Premier plan (Courbe dynamique)* : Une `LineChart` représentant la fréquence cardiaque ou la puissance (Watts) instantanée en superposition.
- **Panneau de Métriques (Grille)** : 
  - Textes massifs avec polices à chasse fixe (Monospaced) pour éviter les sauts de pixels. 
  - Données listées : Fréquence Cardiaque (BPM - rouge), Puissance (Watts - jaune), Distance (km - blanc), Cadence (RPM - bleu), Calories (kcal - orange), Chronomètre (blanc éclatant). 
- **Panneau de Contrôle Latéral (Droite)** : 
  - Deux très gros boutons circulaires `[ + ]` et `[ - ]` (Pente/Résistance), conçus pour être frappés "à l'aveugle" avec un doigt transpirant.
  - Bride logicielle : On ne peut pas descendre sous Pente 0% = Niveau 12 Machine.
- **Footer** : Boutons de contrôle (Play, Pause, Stop).

---

## 3. Architecture Logicielle & Fonctionnalités

L'application adoptera l'architecture MVVM (Model-View-ViewModel) en conjonction avec `@Observable`.

### 3.1. Gestion du Bluetooth (`BluetoothManager`)
Hérite de `CBCentralManagerDelegate`. Gère la Machine d'État (Scan, Connect, Notify).
- **Mécanisme Ping / Keep-alive** : Envoi impératif de la commande de résistance (`0x20 0x01 [LVL] 0x00`) toutes les secondes sur un `Task` asynchrone indépendant.
- **Parsing** : Décodage asynchrone à haute fréquence (0.5s) des trames pages A et B en transformant le BCD propriétaire vers un modèle unique structuré (Vitesse, RPM, Dist, Cal, HR, Watts).
- **Sécurité** : Si la trame n'est plus captée depuis ~3 secondes, déclenchement immédiat du drapeau de Déconnexion.

### 3.2. Moteur de Séances (`PatternEngine`)
- **Dilatation Temporelle** : Le profil de difficulté (ex. Pyramide) est indexé de 0% à 100%. Si l'utilisateur choisit un objectif global de 45 min, la progression est calculée au prorata afin que le motif s'étire.
- **Override Manuel** : Chaque appui sur `+` ou `-` de l'interface modifie la valeur mathématique instantanée calculée, agissant comme un delta "offset".

### 3.3. Santé et Arrière-Plan
- L'utilisation du `HealthKit` (iOS uniquement) s'activera au *Start* et s'arrêtera au *Stop*. Toute donnée captée mettra à jour l'anneau forme du jour de l'utilisateur.
- En cas de fermeture involontaire de l'écran ou de passage sur une autre application (changement de `ScenePhase` vers `.background`), la commande d'arrêt/pause est envoyée nativement pour prévenir un effort trop lourd incontrôlable : la cible de résistance repasse à 12, ou l'exercice est suspendu.

### 3.4. Gestion Locale de la Donnée
- Historique local des records stocké via **SwiftData**, contournant la limite d'Apple Health qui ne connait que le Résumé Global.
- Import/Export via simple fichier JSON depuis les paramètres (facilitant la portabilité).

---

## 4. Setup des Séries d'Exercice (Les "Patterns")
L'app proposera diverses courbes prédéfinies d'intensités modifiées par le moteur de dilatation temporelle.

1. **Plat (Flat)** : Constance parfaite à 0% de pente.
2. **Pascale (Progression continue)** : Montée d'intensité progressive du début à la toute fin.
3. **V-Shape (Vallon)** : Départ à intensité moyenne, descente lente à 0% puis violente remontée vers un pic d'intensité en fin de séance.
4. **Pyramide** : Montée linéaire jusqu'au milieu du temps, puis descente symétrique de récupération.
5. **Alternance / Fractionné (HIIT)** : Répétitions rigoureuses de courts blocs très intenses (pente élevée) séparées de repos stricts.
6. **Combustion (Fat Burn)** : Montée brusque de l'intensité stabilisée sur un haut plateau prolongé visant la zone aérobie pendant 80% du temps.
7. **Escaliers (Steps)** : Augmentation par paliers brusques (sans transition douce). Chaque palier est maintenu quelques minutes.
8. **Colline Vallonnée (Rolling Hills)** : Une suite de vagues fluides, alternant de petites ascensions et descentes douces.
9. **Aléatoire** : La pente varie brutalement et aléatoirement sur des cycles aléatoires pour surprendre l'organisme.
