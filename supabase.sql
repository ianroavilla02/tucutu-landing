-- ============================================================
-- SUPERFANS · Jot4 R — TUCUTÚ (gs-superfans / gs-growthstars-prod)
-- Correr completo en: Supabase Dashboard → SQL Editor
-- ============================================================

-- ---------- 1) TABLAS ----------

create table if not exists public.jot4r_leads (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  source      text default 'landing_tucutu',
  created_at  timestamptz not null default now()
);

create table if not exists public.jot4r_cactus_club (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  name        text,
  city        text,
  instagram   text,
  whatsapp    text,
  created_at  timestamptz not null default now()
);

-- ---------- 2) SEGURIDAD (RLS) ----------
-- Principio: la anon key SOLO puede insertar. Nunca leer, actualizar ni borrar.
-- Así, aunque la key viva en el HTML público de GitHub Pages, nadie puede
-- extraer la lista de correos.

alter table public.jot4r_leads enable row level security;
alter table public.jot4r_cactus_club enable row level security;

drop policy if exists "anon_insert_leads" on public.jot4r_leads;
create policy "anon_insert_leads"
  on public.jot4r_leads for insert
  to anon
  with check (true);

drop policy if exists "anon_insert_club" on public.jot4r_cactus_club;
create policy "anon_insert_club"
  on public.jot4r_cactus_club for insert
  to anon
  with check (true);

-- GRANTs: anon SOLO puede insertar a nivel tabla (requerido por PostgREST).
grant insert on public.jot4r_leads to anon;
grant insert on public.jot4r_cactus_club to anon;

-- Sin policies de SELECT/UPDATE/DELETE para anon → bloqueado por defecto.
-- Duplicados: el UNIQUE en email devuelve 409 que la landing trata como OK.

-- ---------- 3) VISTA DE EXPORTACIÓN PARA META ----------
-- Genera las columnas en el formato que Meta Ads Manager espera para
-- "Audiencia personalizada → Lista de clientes":
--   email (minúsculas), phone (E.164 +57...), fn, ln, ct, country.
-- Incluye cactus_club (boolean) para exportar la lista del club por separado
-- (semilla de mayor calidad para la Lookalike).

create or replace view public.jot4r_meta_export as
select
  lower(trim(l.email)) as email,
  case
    when c.whatsapp is null or btrim(c.whatsapp) = '' then null
    when regexp_replace(c.whatsapp, '\D', '', 'g') ~ '^57\d{10}$'
      then '+' || regexp_replace(c.whatsapp, '\D', '', 'g')
    when length(regexp_replace(c.whatsapp, '\D', '', 'g')) = 10
      then '+57' || regexp_replace(c.whatsapp, '\D', '', 'g')
    else '+' || regexp_replace(c.whatsapp, '\D', '', 'g')
  end as phone,
  lower(split_part(btrim(c.name), ' ', 1))                                   as fn,
  lower(nullif(btrim(substr(btrim(c.name),
        length(split_part(btrim(c.name), ' ', 1)) + 2)), ''))                as ln,
  lower(btrim(c.city))                                                       as ct,
  'co'                                                                       as country,
  (c.email is not null)                                                      as cactus_club,
  l.source,
  l.created_at
from public.jot4r_leads l
left join public.jot4r_cactus_club c using (email);

-- CRÍTICO: las vistas en Postgres se ejecutan como su dueño y saltan RLS.
-- Revocar acceso por API para que solo sea consultable desde el Dashboard
-- (o con la service_role key, que nunca va en el frontend):
revoke all on public.jot4r_meta_export from anon, authenticated;

-- ---------- 4) EXPORTS LISTOS PARA CSV ----------
-- Correr en SQL Editor y usar "Download CSV" del resultado.

-- 4a. Lista completa (todas las descargas):
-- select email, phone, fn, ln, ct, country from public.jot4r_meta_export;

-- 4b. Solo Cactus Club (semilla premium para Lookalike):
-- select email, phone, fn, ln, ct, country from public.jot4r_meta_export where cactus_club;

-- Notas para la subida a Meta:
--  · Ads Manager → Audiencias → Crear → Lista de clientes → subir el CSV.
--  · Meta hashea (SHA-256) en el navegador; no pre-hashear.
--  · Mínimo 100 personas matcheadas (mismo país) para crear la Lookalike;
--    calidad real desde ~1.000 en la semilla.
--  · Lookalike inicial sugerida: 1% Colombia.
