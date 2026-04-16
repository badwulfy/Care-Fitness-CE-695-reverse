import asyncio
from bleak import BleakScanner, BleakClient

# --- Configuration ---
TARGET_NAME_PREFIXES = ["Care", "iConsole", "CE-695", "Kinomap"]
TARGET_LEVEL = 12  # Minimum power (1-32)
PING_INTERVAL = 1.0  # Seconds between sending the power command

# To be discovered automatically
notify_char_uuid = None
write_char_uuid = None

def get_resistance_command(level):
    """Génère la trame hexadécimale pour définir la résistance (1-32)."""
    level = max(1, min(32, int(level)))
    msg = bytearray([0x20, 0x01, level, 0x00])
    checksum = sum(msg) & 0xFF
    msg.append(checksum)
    return msg

def incline_to_resistance(incline_pct):
    """Convertit une pente (0-15%) en niveau de résistance machine (12-32)."""
    incline = max(0.0, min(15.0, float(incline_pct)))
    return int(round(12 + (incline * 20.0 / 15.0)))


def bcd(byte_val):
    """Décode un octet BCD (Binary Coded Decimal) → entier."""
    return (byte_val >> 4) * 10 + (byte_val & 0x0F)

def notification_handler(sender, data):
    """Décode la trame de télémétrie reçue de la machine (valeurs BCD)."""
    hex_data = data.hex()
    
    if len(data) >= 12 and data[0] == 0x20:
        is_page_a = data[1] == 0x00
        b3 = bcd(data[2]) * 100 + bcd(data[3])   # Page A: vitesse×10, Page B: RPM
        dist = bcd(data[4]) * 100 + bcd(data[5])  # Distance (cumulatif)
        cal = bcd(data[6]) * 100 + bcd(data[7])   # Calories (cumulatif)
        hr = data[8]                                # Fréquence cardiaque (décimal, pas BCD)
        watts = bcd(data[9]) * 100 + bcd(data[10]) # Puissance (Watts)


        # Vérification checksum
        calc_chk = sum(data[:11]) & 0xFF
        chk_ok = "✓" if calc_chk == data[11] else "✗"

        if is_page_a:
            speed_kmh = b3 / 10.0
            info = f"SPD: {speed_kmh:4.1f} km/h | W: {watts:3d} | D: {dist}"
        else:
            info = f"RPM: {b3:3d}       | W: {watts:3d} | D: {dist}"
        
        if cal > 0:
            info += f" | Cal={cal}"
        if hr > 0:
            info += f" | ♥{hr} bpm"

        print(f"[REÇU] {info}  (Brut: {hex_data})")
    elif len(data) >= 9 and data[0] == 0x40:
        print(f"[REÇU] Config/Setup: {hex_data}")
    else:
        print(f"[REÇU] Inconnu ({len(data)}B): {hex_data}")

async def main():
    global notify_char_uuid, write_char_uuid

    target_device = None
    attempt = 0
    while target_device is None:
        attempt += 1
        print(f"Recherche de l'elliptique (tentative {attempt})...")
        devices = await BleakScanner.discover(timeout=5.0)
        
        for d in devices:
            name = d.name or "Inconnu"
            for prefix in TARGET_NAME_PREFIXES:
                if prefix.lower() in name.lower():
                    target_device = d
                    break
            if target_device:
                break
                
        if not target_device:
            print(f"  Pas trouvé parmi {len(devices)} appareils. Nouvel essai dans 5s...")
            await asyncio.sleep(5)

    print(f"\nAppareil ciblé : {target_device.name} [{target_device.address}]")
    print(f"Connexion en cours...")

    async with BleakClient(target_device.address) as client:
        print("Connecté !")
        
        # --- Découverte des caractéristiques ---
        print("\nServices GATT :")
        for service in client.services:
            print(f"  Service: {service.uuid}")
            for char in service.characteristics:
                props = ", ".join(char.properties)
                print(f"    Char: {char.uuid} [{props}]")
                
                # Skip Battery Level (2a19)
                if "2a19" in str(char.uuid).lower():
                    continue
                
                if "notify" in char.properties or "indicate" in char.properties:
                    notify_char_uuid = char.uuid
                if "write-without-response" in char.properties or "write" in char.properties:
                    write_char_uuid = char.uuid
                    
        if not write_char_uuid or not notify_char_uuid:
            print("Erreur: Impossible de trouver les caractéristiques.")
            return
            
        print(f"\nUUID écriture  : {write_char_uuid}")
        print(f"UUID notification: {notify_char_uuid}")

        # --- Écoute ---
        await client.start_notify(notify_char_uuid, notification_handler)
        print("Écoute télémétrie démarrée.\n")

        # --- Boucle keep-alive + résistance ---
        print(f"Envoi résistance niveau {TARGET_LEVEL} toutes les {PING_INTERVAL}s")
        print("Ctrl+C pour arrêter.\n")
        
        try:
            while True:
                cmd = get_resistance_command(TARGET_LEVEL)
                await client.write_gatt_char(write_char_uuid, cmd, response=False)
                print(f"[ENVOI] Résistance → {TARGET_LEVEL} ({cmd.hex()})")
                await asyncio.sleep(PING_INTERVAL)
        except (asyncio.CancelledError, KeyboardInterrupt):
            pass
        finally:
            print("\nArrêt...")
            await client.stop_notify(notify_char_uuid)
            print("Déconnecté.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nProgramme terminé.")
