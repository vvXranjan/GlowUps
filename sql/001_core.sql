-- BookMyStyle core schema for Supabase (Postgres 15+)
-- Run in the Supabase SQL editor. Tested on Postgres 16 with a 2-stylist seed:
-- slots, holds, overlap blocking, hold expiry, time off and customer stats all checked.
-- Not yet tested: RLS with real Supabase Auth logins.

create extension if not exists btree_gist;
create extension if not exists pgcrypto;

create table businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text not null default 'salon',
  address text,
  maps_url text,
  phone text,
  timezone text not null default 'Asia/Kolkata',
  slot_step_min int not null default 15 check (slot_step_min in (5,10,15,30)),
  min_notice_min int not null default 30,
  booking_horizon_days int not null default 14,
  settings jsonb not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table business_whatsapp_numbers (
  phone_number_id text primary key,
  business_id uuid not null references businesses(id) on delete cascade,
  waba_id text not null,
  display_phone text not null,
  is_active boolean not null default true
);

create table business_hours (
  business_id uuid not null references businesses(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7), -- ISO: 1 = Monday
  open_time time not null,
  close_time time not null check (close_time > open_time),
  primary key (business_id, weekday)
);

create table business_members (
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','manager')),
  primary key (business_id, user_id)
);

create table staff (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  phone text,
  role text not null check (role in ('owner','manager','stylist','reception')),
  is_bookable boolean not null default true,
  is_active boolean not null default true,
  unique (business_id, phone)
);

create table services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  aliases text[] not null default '{}',  -- e.g. {'cutting','baal katwana'}
  category text,
  price_paise int not null check (price_paise >= 0),
  price_is_from boolean not null default false, -- "starts at"
  duration_min int not null check (duration_min > 0),
  buffer_min int not null default 0,
  description text,
  is_active boolean not null default true,
  unique (business_id, name)
);

create table staff_services (
  staff_id uuid not null references staff(id) on delete cascade,
  service_id uuid not null references services(id) on delete cascade,
  primary key (staff_id, service_id)
);

create table staff_working_hours (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null check (end_time > start_time)
);

create table staff_time_off (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null check (end_at > start_at),
  reason text
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  wa_phone text not null,
  name text,
  gender text,
  birthday date,
  preferred_staff_id uuid references staff(id),
  preferred_language text default 'en',
  marketing_opt_in boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (business_id, wa_phone)
);

create table consent_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  kind text not null check (kind in ('marketing_opt_in','marketing_opt_out','all_opt_out')),
  source text not null, -- 'whatsapp_reply','in_salon_form','import'
  evidence text,
  created_at timestamptz not null default now()
);

create table appointments (
  id uuid primary key default gen_random_uuid(),
  short_code int generated always as identity, -- "appointment 102"
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id),
  service_id uuid not null references services(id),
  staff_id uuid not null references staff(id),
  start_at timestamptz not null,
  end_at timestamptz not null check (end_at > start_at),
  status text not null check (status in
    ('held','confirmed','completed','cancelled','no_show','expired')),
  hold_expires_at timestamptz,
  source text not null default 'whatsapp', -- whatsapp | staff | dashboard
  reminder_24h_sent_at timestamptz,
  reminder_2h_sent_at timestamptz,
  cancelled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_staff_overlap exclude using gist (
    staff_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status in ('held','confirmed'))
);

create table visits (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id),
  appointment_id uuid unique references appointments(id),
  service_id uuid not null references services(id),
  staff_id uuid references staff(id),
  visited_at timestamptz not null default now(),
  recorded_by uuid references staff(id),
  is_walk_in boolean not null default false
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  visit_id uuid not null references visits(id),
  amount_paise int not null check (amount_paise >= 0),
  method text not null check (method in ('cash','upi','card','package','other')),
  paid_at timestamptz not null default now(),
  recorded_by uuid references staff(id)
);

create table feedback (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  visit_id uuid not null references visits(id),
  rating smallint check (rating between 1 and 5),
  comment text,
  needs_follow_up boolean generated always as (rating <= 3) stored,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table conversations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  bot_paused_until timestamptz,
  last_inbound_at timestamptz, -- 24h window = last_inbound_at + 24h
  state jsonb not null default '{}', -- short-term memory: pending hold, last offer
  unique (business_id, customer_id)
);

create table messages (
  id bigint generated always as identity primary key,
  business_id uuid not null references businesses(id) on delete cascade,
  conversation_id uuid references conversations(id) on delete cascade,
  wamid text unique, -- dedupe key
  direction text not null check (direction in ('in','out')),
  sender_role text not null check (sender_role in ('customer','staff','owner','bot','human')),
  msg_type text not null, -- text, interactive, audio, template, status
  body text,
  template_name text,
  status text, -- sent, delivered, read, failed
  raw jsonb,
  created_at timestamptz not null default now()
);

create table audit_log (
  id bigint generated always as identity primary key,
  business_id uuid not null,
  actor text not null, -- 'bot', 'staff:<id>', 'user:<id>', 'system'
  action text not null,
  entity text,
  entity_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

create index on appointments (business_id, start_at);
create index on appointments (customer_id, start_at desc);
create index on appointments (status, start_at) where status = 'confirmed';
create index on visits (business_id, visited_at desc);
create index on visits (customer_id, visited_at desc);
create index on payments (business_id, paid_at desc);
create index on messages (conversation_id, created_at desc);
create index on staff_working_hours (staff_id, weekday);
create index on staff_time_off (staff_id, start_at);

create view customer_stats with (security_invoker = true) as
select c.id as customer_id, c.business_id,
  count(v.id) as total_visits,
  max(v.visited_at) as last_visit_at,
  coalesce(sum(v.paid), 0) as lifetime_paise,
  case when count(v.id) >= 2 then
    round(extract(epoch from max(v.visited_at) - min(v.visited_at)) / 86400 / (count(v.id) - 1), 1)
  end as avg_gap_days
from customers c
left join (
  select vi.id, vi.customer_id, vi.visited_at,
    (select coalesce(sum(p.amount_paise), 0) from payments p where p.visit_id = vi.id) as paid
  from visits vi
) v on v.customer_id = c.id
group by c.id, c.business_id;

-- 1. Free slots for a service on a date
create or replace function get_available_slots(
  p_business uuid, p_service uuid, p_date date, p_staff uuid default null)
returns table (staff_id uuid, staff_name text, slot_start timestamptz)
language sql stable as $$
  with svc as (
    select duration_min + buffer_min as len from services
    where id = p_service and business_id = p_business and is_active),
  biz as (select timezone, slot_step_min, min_notice_min from businesses where id = p_business),
  shifts as (
    select s.id, s.name,
      (p_date + wh.start_time) at time zone biz.timezone as from_at,
      (p_date + wh.end_time)   at time zone biz.timezone as to_at
    from staff s
    join staff_services ss on ss.staff_id = s.id and ss.service_id = p_service
    join staff_working_hours wh on wh.staff_id = s.id
         and wh.weekday = extract(isodow from p_date)
    cross join biz
    where s.business_id = p_business and s.is_active and s.is_bookable
      and (p_staff is null or s.id = p_staff)),
  slots as (
    select sh.id, sh.name, g as st, g + make_interval(mins => svc.len) as en
    from shifts sh cross join svc cross join biz,
    lateral generate_series(sh.from_at, sh.to_at - make_interval(mins => svc.len),
                            make_interval(mins => biz.slot_step_min)) g)
  select sl.id, sl.name, sl.st from slots sl, biz
  where sl.st >= now() + make_interval(mins => biz.min_notice_min)
    and not exists (
      select 1 from appointments a
      where a.staff_id = sl.id
        and (a.status = 'confirmed' or (a.status = 'held' and a.hold_expires_at > now()))
        and tstzrange(a.start_at, a.end_at, '[)') && tstzrange(sl.st, sl.en, '[)'))
    and not exists (
      select 1 from staff_time_off t
      where t.staff_id = sl.id
        and tstzrange(t.start_at, t.end_at, '[)') && tstzrange(sl.st, sl.en, '[)'))
  order by sl.st, sl.name;
$$;

-- 2. Hold a slot for 10 minutes
create or replace function hold_slot(
  p_business uuid, p_customer uuid, p_service uuid, p_staff uuid, p_start timestamptz)
returns uuid language plpgsql as $$
declare v_len int; v_id uuid;
begin
  update appointments set status = 'expired', updated_at = now()
   where staff_id = p_staff and status = 'held' and hold_expires_at <= now();

  if not exists (
    select 1 from get_available_slots(p_business, p_service,
      (p_start at time zone (select timezone from businesses where id = p_business))::date, p_staff)
    where slot_start = p_start) then
    raise exception 'SLOT_NOT_AVAILABLE';
  end if;

  -- only one active hold per customer
  update appointments set status = 'expired', updated_at = now()
   where customer_id = p_customer and status = 'held';

  select duration_min + buffer_min into v_len from services where id = p_service;

  insert into appointments (business_id, customer_id, service_id, staff_id,
    start_at, end_at, status, hold_expires_at)
  values (p_business, p_customer, p_service, p_staff,
    p_start, p_start + make_interval(mins => v_len), 'held', now() + interval '10 minutes')
  returning id into v_id;
  return v_id;
exception when exclusion_violation then
  raise exception 'SLOT_TAKEN';
end $$;

-- 3. Confirm only after the customer says yes
create or replace function confirm_appointment(p_business uuid, p_customer uuid, p_appointment uuid)
returns void language plpgsql as $$
begin
  update appointments set status = 'confirmed', hold_expires_at = null, updated_at = now()
   where id = p_appointment and business_id = p_business and customer_id = p_customer
     and status = 'held' and hold_expires_at > now();
  if not found then raise exception 'HOLD_EXPIRED'; end if;
  insert into audit_log (business_id, actor, action, entity, entity_id)
  values (p_business, 'bot', 'appointment_confirmed', 'appointment', p_appointment::text);
end $$;

create or replace function my_business_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select business_id from business_members where user_id = auth.uid()
$$;

alter table appointments enable row level security;
create policy tenant_read on appointments for select
  using (business_id in (select my_business_ids()));
create policy tenant_write on appointments for all
  using (business_id in (select my_business_ids()))
  with check (business_id in (select my_business_ids()));

alter table staff_working_hours enable row level security;
create policy tenant_all on staff_working_hours for all
  using (staff_id in (select id from staff where business_id in (select my_business_ids())));

revoke execute on function get_available_slots, hold_slot, confirm_appointment
  from public, anon, authenticated;
