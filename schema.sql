-- O'ZBEKISTON KELAJAGI — Supabase sxemasi. SQL Editor'da bir marta ishga tushiring.
create extension if not exists pgcrypto;

create table votes(id bigint generated always as identity primary key,
  choice smallint not null check (choice between 1 and 4), created_at timestamptz default now());
create table tokens(token uuid primary key default gen_random_uuid(),
  used boolean not null default false, created_at timestamptz default now()); -- ovozga BOG'LANMAGAN
create table receipts(code text primary key, vote_id bigint unique references votes(id),
  created_at timestamptz default now());
create table admin_secret(hash text not null);
create table admin_sessions(token text primary key, expires timestamptz not null);
create table admin_attempts(at timestamptz default now());

-- RLS yoqilgan, siyosat yo'q: jadvallarga to'g'ridan-to'g'ri kirish butunlay yopiq.
alter table votes enable row level security;
alter table tokens enable row level security;
alter table receipts enable row level security;
alter table admin_secret enable row level security;
alter table admin_sessions enable row level security;
alter table admin_attempts enable row level security;

-- !!! 'SIZNING_MAXFIY_KODINGIZ' o'rniga o'z kodingizni yozing (bu faylni kodingiz bilan GitHub'ga yuklamang).
insert into admin_secret(hash) values (crypt('SIZNING_MAXFIY_KODINGIZ', gen_salt('bf')));

create function issue_token() returns uuid language sql security definer set search_path=public as
$$ insert into tokens default values returning token $$;

create or replace function cast_vote(p_token uuid, p_choice int) returns text
language plpgsql security definer set search_path=public as $$
declare vid bigint; h text; c text;
begin
  if p_choice not in (2,3,4) then raise exception 'BAD_CHOICE'; end if;
  update tokens set used=true where token=p_token and used=false;
  if not found then raise exception 'TOKEN_USED'; end if;
  insert into votes(choice) values (p_choice) returning id into vid;
  h := upper(encode(gen_random_bytes(6),'hex'));
  c := 'BK-'||substr(h,1,4)||'-'||substr(h,5,4)||'-'||substr(h,9,4);
  insert into receipts(code,vote_id) values (c,vid);
  return c;
end $$;

create function admin_login(pw text) returns text
language plpgsql security definer set search_path=public as $$
declare t text;
begin
  if (select count(*) from admin_attempts where at > now()-interval '10 minutes') >= 5
    then raise exception 'LOCKED'; end if;
  if exists(select 1 from admin_secret where hash = crypt(pw,hash)) then
    t := encode(gen_random_bytes(24),'hex');
    insert into admin_sessions values (t, now()+interval '2 hours');
    return t;
  end if;
  insert into admin_attempts default values;
  raise exception 'BAD_PASSWORD';
end $$;

create function _chk(t text) returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from admin_sessions where token=t and expires>now()) then raise exception 'AUTH'; end if;
end $$;

create function admin_stats(t text) returns json
language plpgsql security definer set search_path=public as $$
begin
  perform _chk(t);
  return json_build_object(
    'counts', (select json_object_agg(g, coalesce(n,0)) from generate_series(1,4) g
               left join (select choice, count(*) n from votes group by 1) v on v.choice=g),
    'total', (select count(*) from votes),
    'receipts', (select count(*) from receipts),
    'last', (select coalesce(json_agg(x),'[]'::json) from
             (select id, created_at from votes order by id desc limit 20) x),
    'server_time', now());
end $$;

create function admin_codes(t text) returns text
language plpgsql security definer set search_path=public as $$
begin perform _chk(t);
  return coalesce((select string_agg(code, E'\n' order by created_at) from receipts),'');
end $$;

create function admin_find(t text, c text) returns boolean
language plpgsql security definer set search_path=public as $$
begin perform _chk(t);
  return exists(select 1 from receipts where code=upper(trim(c)));
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function issue_token(), cast_vote(uuid,int), admin_login(text),
  admin_stats(text), admin_codes(text), admin_find(text,text) to anon;
