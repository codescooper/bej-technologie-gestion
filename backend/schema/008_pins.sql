-- =====================================================================
-- BEJ Technologie — Durcissement : empreintes PBKDF2 des PIN (§6)
--
-- Remplace les PIN stockés en clair par leur empreinte PBKDF2-HMAC-SHA256
-- (sel = id utilisateur, 50 000 tours ; cf. app/lib/src/util/pin_hash.dart).
-- Les PIN d'usage restent 1111 / 2222 / 3333 / 4444 (seule l'empreinte change).
-- À exécuter après 001..007.
-- =====================================================================

UPDATE utilisateurs SET mot_de_passe_hash =
  'e81898846706852726b5bf4d66574b80928366365debd255d3cc1b279e9064f0'
  WHERE id = '0e000000-0000-4000-8000-000000000001'; -- admin (1111)

UPDATE utilisateurs SET mot_de_passe_hash =
  '605d87c7bcda7bd02fde79de257aa93432e049f546e764a369ffee0b5394b13c'
  WHERE id = '0e000000-0000-4000-8000-000000000002'; -- awa, caissier (2222)

UPDATE utilisateurs SET mot_de_passe_hash =
  '72fb4d8904996702a7c242a9f52a55a16645d5dd208db9c04c3230ca8b7f811a'
  WHERE id = '0e000000-0000-4000-8000-000000000003'; -- ben, responsable (3333)

UPDATE utilisateurs SET mot_de_passe_hash =
  'bcd31a2c483b11414a37c3b9e1ffa1480b68edc7cd9dafc90de0788df6b1a1db'
  WHERE id = '0e000000-0000-4000-8000-000000000004'; -- koffi, technicien (4444)
