-- ===========================================================
--  Сервер для общей таблицы «Лесные приключения»
--  Как использовать: Supabase → SQL Editor → New query → вставь ВЕСЬ этот текст → Run
--  ПЕРЕД запуском замени ВАШ_СЕКРЕТНЫЙ_КОД_АДМИНА (он встречается один раз, ниже) на свой пароль администратора
--  (латинские буквы и цифры, лучше длинный). Знающий этот пароль сможет удалять игроков.
-- ===========================================================

create table if not exists public.players (
  room text not null,
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (room, id)
);
create table if not exists public.app_secret (k text primary key, v text not null);

alter table public.players enable row level security;
alter table public.app_secret enable row level security;
revoke all on public.players from anon, authenticated;
revoke all on public.app_secret from anon, authenticated;

insert into public.app_secret (k, v) values ('admin_key', 'pochemuchka24')
  on conflict (k) do update set v = excluded.v;

-- игрок сохраняет свои результаты
create or replace function public.upsert_player(p_room text, p_id text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_room !~ '^[A-Za-z0-9_-]{3,24}$' then raise exception 'bad room'; end if;
  if p_id !~ '^[A-Za-z0-9_-]{4,40}$' then raise exception 'bad id'; end if;
  if jsonb_typeof(p_data) <> 'object' or length(p_data::text) > 30000 then raise exception 'bad data'; end if;
  if length(coalesce(p_data->>'name','')) not between 1 and 12 then raise exception 'bad name'; end if;
  if (select count(*) from players where room = p_room) >= 40
     and not exists (select 1 from players where room = p_room and id = p_id) then
    raise exception 'room full';
  end if;
  insert into players (room, id, data) values (p_room, p_id, p_data)
  on conflict (room, id) do update set data = excluded.data, updated_at = now();
end $$;

-- игрок читает СВОЙ полный профиль (чтобы прогресс не терялся)
create or replace function public.get_me(p_room text, p_id text)
returns jsonb language sql security definer set search_path = public as $$
  select data from players where room = p_room and id = p_id
$$;

-- таблица героев комнаты (только то, что нужно для рейтинга)
create or replace function public.get_players(p_room text)
returns table (id text, data jsonb) language sql security definer set search_path = public as $$
  select p.id, jsonb_build_object(
      'name', p.data->'name', 'av', p.data->'av', 'stars', p.data->'stars',
      'st', jsonb_build_object('tot', p.data#>'{st,tot}', 'ok', p.data#>'{st,ok}', 'best', p.data#>'{st,best}'))
  from players p where p.room = p_room order by p.updated_at desc limit 40
$$;

-- администратор: убрать одного игрока
create or replace function public.admin_delete_player(p_room text, p_id text, p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_key is distinct from (select v from app_secret where k = 'admin_key') then raise exception 'wrong admin key'; end if;
  delete from players where room = p_room and id = p_id;
end $$;

-- администратор: очистить всю комнату
create or replace function public.admin_clear_room(p_room text, p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_key is distinct from (select v from app_secret where k = 'admin_key') then raise exception 'wrong admin key'; end if;
  delete from players where room = p_room;
end $$;

grant execute on function public.upsert_player(text, text, jsonb) to anon, authenticated;
grant execute on function public.get_me(text, text) to anon, authenticated;
grant execute on function public.get_players(text) to anon, authenticated;
grant execute on function public.admin_delete_player(text, text, text) to anon, authenticated;
grant execute on function public.admin_clear_room(text, text) to anon, authenticated;
