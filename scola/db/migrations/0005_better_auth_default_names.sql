-- =====================================================================
-- 0005_better_auth_default_names.sql
-- Aligne les tables de connexion (schéma `auth`) sur les noms par défaut
-- de Better Auth, pour que sa configuration n'ait aucune correspondance
-- de tables ou de colonnes à déclarer.
--
-- Renommages uniquement : aucune donnée supprimée. Les clés étrangères,
-- index, droits et déclencheurs suivent automatiquement.
-- =====================================================================

do $$
declare
  r record;
begin
  -- Colonnes : (table actuelle, ancien nom, nouveau nom)
  for r in
    select * from (values
      ('users',         'email_verified',            'emailVerified'),
      ('users',         'two_factor_enabled',        'twoFactorEnabled'),
      ('users',         'created_at',                'createdAt'),
      ('users',         'updated_at',                'updatedAt'),
      ('sessions',      'user_id',                   'userId'),
      ('sessions',      'expires_at',                'expiresAt'),
      ('sessions',      'ip_address',                'ipAddress'),
      ('sessions',      'user_agent',                'userAgent'),
      ('sessions',      'created_at',                'createdAt'),
      ('sessions',      'updated_at',                'updatedAt'),
      ('accounts',      'user_id',                   'userId'),
      ('accounts',      'account_id',                'accountId'),
      ('accounts',      'provider_id',               'providerId'),
      ('accounts',      'access_token',              'accessToken'),
      ('accounts',      'refresh_token',             'refreshToken'),
      ('accounts',      'id_token',                  'idToken'),
      ('accounts',      'access_token_expires_at',   'accessTokenExpiresAt'),
      ('accounts',      'refresh_token_expires_at',  'refreshTokenExpiresAt'),
      ('accounts',      'created_at',                'createdAt'),
      ('accounts',      'updated_at',                'updatedAt'),
      ('verifications', 'expires_at',                'expiresAt'),
      ('verifications', 'created_at',                'createdAt'),
      ('verifications', 'updated_at',                'updatedAt'),
      ('two_factors',   'user_id',                   'userId'),
      ('two_factors',   'backup_codes',              'backupCodes'),
      ('two_factors',   'failed_verification_count', 'failedVerificationCount'),
      ('two_factors',   'locked_until',              'lockedUntil')
    ) as t(tbl, old_name, new_name)
  loop
    execute format('alter table auth.%I rename column %I to %I', r.tbl, r.old_name, r.new_name);
  end loop;

  -- Tables : (ancien nom, nouveau nom)
  for r in
    select * from (values
      ('users',         'user'),
      ('sessions',      'session'),
      ('accounts',      'account'),
      ('verifications', 'verification'),
      ('two_factors',   'twoFactor')
    ) as t(old_name, new_name)
  loop
    execute format('alter table auth.%I rename to %I', r.old_name, r.new_name);
  end loop;
end;
$$;

-- La connexion de l'application (scola_app) trouve les tables de Better
-- Auth sans préfixe : `user` désigne auth."user". Le schéma public reste
-- accessible ensuite ; aucun nom de table n'y entre en conflit.
alter role scola_app set search_path = auth, public;
