-- Supabase SQL (v5): オノマトペ早押し対戦
-- 1) Supabase Auth で Anonymous Sign-in を有効化
-- 2) このSQLをSQL Editorで実行
-- 3) 問題作成はログイン後、誰でも可能。作成者は自分の問題を編集/非公開化できます。

create extension if not exists pgcrypto;

drop table if exists public.answer_reactions cascade;
drop table if exists public.round_answers cascade;
drop table if exists public.room_questions cascade;
drop table if exists public.question_bank cascade;
drop table if exists public.players cascade;
drop table if exists public.rooms cascade;

create table public.question_bank(
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null,
 word1 text not null check(length(trim(word1)) between 1 and 30),
 word2 text not null check(length(trim(word2)) between 1 and 30),
 category text not null default '日常',
 answer text not null check(length(trim(answer)) between 1 and 120),
 accepted_answers text[] not null default '{}',
 difficulty int not null default 2 check(difficulty between 1 and 3),
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.rooms(
 id uuid primary key default gen_random_uuid(),
 code text unique not null check(length(code)=4),
 host_user_id uuid not null,
 status text not null default 'lobby' check(status in ('lobby','playing','finished')),
 phase text not null default 'question' check(phase in ('question','result')),
 question_no int not null default 0,
 question_deadline timestamptz,
 result_deadline timestamptz,
 buzzed_by uuid,
 current_question_id uuid,
 created_at timestamptz not null default now()
);

create table public.players(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 user_id uuid not null,
 name text not null check(length(name) between 1 and 12),
 ready boolean not null default false,
 score int not null default 0,
 buzzed_at timestamptz,
 joined_at timestamptz not null default now(),
 unique(room_id,user_id),
 unique(room_id,name)
);

create table public.room_questions(
 room_id uuid not null references public.rooms(id) on delete cascade,
 question_no int not null check(question_no between 0 and 9),
 question_id uuid not null references public.question_bank(id),
 primary key(room_id,question_no)
);

create table public.round_answers(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 question_no int not null,
 user_id uuid not null,
 answer text not null,
 correct boolean not null,
 points int not null default 0,
 created_at timestamptz not null default now(),
 unique(room_id,question_no)
);

create table public.answer_reactions(
 id uuid primary key default gen_random_uuid(),
 answer_id uuid not null references public.round_answers(id) on delete cascade,
 user_id uuid not null,
 reaction text not null check(reaction in ('good','bad')),
 created_at timestamptz not null default now(),
 unique(answer_id,user_id)
);

alter table public.question_bank enable row level security;
alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.room_questions enable row level security;
alter table public.round_answers enable row level security;
alter table public.answer_reactions enable row level security;

create policy "questions read" on public.question_bank for select to authenticated using (true);
create policy "questions insert own" on public.question_bank for insert to authenticated with check (created_by=auth.uid());
create policy "questions update own" on public.question_bank for update to authenticated using (created_by=auth.uid()) with check (created_by=auth.uid());

create policy "rooms read" on public.rooms for select to authenticated using (true);
create policy "players read" on public.players for select to authenticated using (true);
create policy "room questions read" on public.room_questions for select to authenticated using (true);
create policy "answers read" on public.round_answers for select to authenticated using (true);
create policy "reactions read" on public.answer_reactions for select to authenticated using (true);

create or replace function public.create_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rid uuid; c text:=upper(trim(p_code));
begin
 insert into rooms(code,host_user_id) values(c,auth.uid()) returning id into rid;
 insert into players(room_id,user_id,name) values(rid,auth.uid(),left(trim(p_name),12));
 return jsonb_build_object('room_id',rid);
end $$;

create or replace function public.join_room(p_code text,p_name text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms; clean_name text:=left(trim(p_name),12);
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if r.id is null then raise exception 'ルームが見つかりません'; end if;
 if r.status<>'lobby' then raise exception 'このゲームはすでに開始しています'; end if;
 if (select count(*) from players where room_id=r.id)>=4 and not exists(select 1 from players where room_id=r.id and user_id=auth.uid()) then raise exception '満員です'; end if;
 if exists(select 1 from players where room_id=r.id and name=clean_name and user_id<>auth.uid()) then raise exception 'そのプレイヤー名は使用中です'; end if;
 insert into players(room_id,user_id,name) values(r.id,auth.uid(),clean_name)
 on conflict(room_id,user_id) do update set name=excluded.name;
 return jsonb_build_object('room_id',r.id);
end $$;

create or replace function public.set_ready(p_room_id uuid,p_ready boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from players where room_id=p_room_id and user_id=auth.uid()) then raise exception '参加者ではありません'; end if;
 update players set ready=p_ready where room_id=p_room_id and user_id=auth.uid();
end $$;

create or replace function public.start_game(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare ids uuid[]; i int:=0; qid uuid; r rooms;
begin
 select * into r from rooms where id=p_room_id for update;
 if r.host_user_id<>auth.uid() then raise exception 'ホストだけが開始できます'; end if;
 if (select count(*) from players where room_id=p_room_id)<2 then raise exception '2人以上で開始してください'; end if;
 if exists(select 1 from players where room_id=p_room_id and ready=false) then raise exception '全員がREADYになってから開始してください'; end if;
 delete from room_questions where room_id=p_room_id;
 select array_agg(id order by random()) into ids from question_bank where is_active=true;
 if coalesce(array_length(ids,1),0)<10 then raise exception '公開中の問題を10問以上用意してください'; end if;
 while i<10 loop
   qid:=ids[i+1]; insert into room_questions(room_id,question_no,question_id) values(p_room_id,i,qid); i:=i+1;
 end loop;
 select question_id into qid from room_questions where room_id=p_room_id and question_no=0;
 update rooms set status='playing',phase='question',question_no=0,current_question_id=qid,question_deadline=now()+interval '10 seconds',result_deadline=null,buzzed_by=null where id=p_room_id and status='lobby';
end $$;

create or replace function public.claim_buzz(p_room_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare changed int;
begin
 if p_user_id<>auth.uid() then raise exception '認証エラー'; end if;
 update rooms set buzzed_by=p_user_id where id=p_room_id and status='playing' and phase='question' and buzzed_by is null and question_deadline>now();
 get diagnostics changed=row_count;
 if changed=1 then
   update players set buzzed_at=now() where room_id=p_room_id and user_id=p_user_id;
   return jsonb_build_object('claimed',true);
 end if;
 return jsonb_build_object('claimed',false);
end $$;

create or replace function public.submit_answer(p_room_id uuid,p_user_id uuid,p_answer text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms; q question_bank; hit boolean:=false; k text; pts int:=0; aid uuid;
begin
 if p_user_id<>auth.uid() then raise exception '認証エラー'; end if;
 select * into r from rooms where id=p_room_id for update;
 if r.status<>'playing' or r.phase<>'question' or r.buzzed_by<>p_user_id then raise exception '回答権がありません'; end if;
 select * into q from question_bank where id=r.current_question_id;
 foreach k in array q.accepted_answers loop if length(trim(k))>0 and position(lower(trim(k)) in lower(p_answer))>0 then hit:=true; exit; end if; end loop;
 if not hit and position(lower(trim(q.answer)) in lower(p_answer))>0 then hit:=true; end if;
 if hit then pts:=100; end if;
 insert into round_answers(room_id,question_no,user_id,answer,correct,points) values(r.id,r.question_no,p_user_id,left(p_answer,120),hit,pts) returning id into aid;
 update players set score=score+pts where room_id=r.id and user_id=p_user_id;
 update rooms set phase='result',result_deadline=now()+interval '5 seconds',question_deadline=null where id=r.id;
 return jsonb_build_object('answer_id',aid,'correct',hit,'points',pts,'official_answer',q.answer);
end $$;

create or replace function public.react_answer(p_answer_id uuid,p_reaction text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rid uuid; uid uuid:=auth.uid();
begin
 if p_reaction not in ('good','bad') then raise exception '不正なリアクションです'; end if;
 select room_id into rid from round_answers where id=p_answer_id;
 if rid is null or not exists(select 1 from players where room_id=rid and user_id=uid) then raise exception '参加者ではありません'; end if;
 insert into answer_reactions(answer_id,user_id,reaction) values(p_answer_id,uid,p_reaction)
 on conflict(answer_id,user_id) do update set reaction=excluded.reaction,created_at=now();
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.next_round(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; q int; next_qid uuid;
begin
 select * into r from rooms where id=p_room_id for update;
 if r.host_user_id<>auth.uid() then raise exception 'ホストだけが次の問題へ進めます'; end if;
 if r.status<>'playing' or r.phase<>'result' then return; end if;
 q:=r.question_no;
 if q>=9 then
   update rooms set status='finished',phase='question',question_deadline=null,result_deadline=null,buzzed_by=null where id=p_room_id;
 else
   select question_id into next_qid from room_questions where room_id=p_room_id and question_no=q+1;
   update players set buzzed_at=null where room_id=p_room_id;
   update rooms set question_no=q+1,current_question_id=next_qid,phase='question',question_deadline=now()+interval '10 seconds',result_deadline=null,buzzed_by=null where id=p_room_id;
 end if;
end $$;

create or replace function public.rematch_room(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where id=p_room_id for update;
 if r.host_user_id<>auth.uid() then raise exception 'ホストだけが再戦できます'; end if;
 delete from room_questions where room_id=p_room_id;
 delete from round_answers where room_id=p_room_id;
 update players set score=0,buzzed_at=null,ready=false where room_id=p_room_id;
 update rooms set status='lobby',phase='question',question_no=0,current_question_id=null,question_deadline=null,result_deadline=null,buzzed_by=null where id=p_room_id;
end $$;

create or replace function public.timeout_round(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where id=p_room_id for update;
 if r.host_user_id<>auth.uid() then raise exception 'ホストではありません'; end if;
 if r.status='playing' and r.phase='question' and r.question_deadline<=now() then
   update rooms set phase='result',result_deadline=now()+interval '4 seconds',question_deadline=null where id=p_room_id;
 end if;
end $$;

create or replace function public.create_question(p_word1 text,p_word2 text,p_category text,p_answer text,p_accepted_answers text[],p_difficulty int)
returns uuid language plpgsql security definer set search_path=public as $$
declare qid uuid;
begin
 insert into question_bank(created_by,word1,word2,category,answer,accepted_answers,difficulty)
 values(auth.uid(),left(trim(p_word1),30),left(trim(p_word2),30),left(trim(p_category),20),left(trim(p_answer),120),p_accepted_answers,greatest(1,least(3,p_difficulty))) returning id into qid;
 return qid;
end $$;

create or replace function public.set_question_active(p_question_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 update question_bank set is_active=p_active,updated_at=now() where id=p_question_id and created_by=auth.uid();
end $$;

grant execute on function public.create_room(text,text) to authenticated;
grant execute on function public.join_room(text,text) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;
grant execute on function public.claim_buzz(uuid,uuid) to authenticated;
grant execute on function public.submit_answer(uuid,uuid,text) to authenticated;
grant execute on function public.react_answer(uuid,text) to authenticated;
grant execute on function public.next_round(uuid) to authenticated;
grant execute on function public.set_ready(uuid,boolean) to authenticated;
grant execute on function public.rematch_room(uuid) to authenticated;
grant execute on function public.create_question(text,text,text,text,text[],int) to authenticated;
grant execute on function public.set_question_active(uuid,boolean) to authenticated;

-- 初期問題10問。実運用では画面から追加できます。
insert into question_bank(created_by,word1,word2,category,answer,accepted_answers,difficulty)
select '00000000-0000-0000-0000-000000000000'::uuid,* from (values
('ピンポーン','ガチャ','日常','インターホンが鳴って、玄関のドアを開けた',array['インターホン','ドア','玄関'],1),
('バシャーン','キャー！','レジャー','誰かがプールや海に飛び込んだ',array['プール','海','水','飛び込'],1),
('カタカタ','ピコン！','デジタル','パソコンを操作して、通知が届いた',array['パソコン','PC','通知','スマホ'],1),
('ドン！','シーン…','日常','何かが落ちて、その場が静かになった',array['落','静か','倒'],2),
('ガチャガチャ','バタン！','日常','鍵を開けて、ドアを閉めた',array['鍵','ドア','扉'],1),
('ゴロゴロ','ピカッ！','自然','雷が鳴って、稲妻が光った',array['雷','稲妻'],1),
('ジュージュー','パチパチ','食べ物','肉を焼いている',array['焼','肉','料理','鉄板'],1),
('ザアザア','ゴロゴロ','自然','雨が降って雷も鳴っている',array['雨','雷','嵐'],1),
('カンカン','キーン','音','鐘が鳴り、耳に響いている',array['鐘','ベル','音'],2),
('シュッ','ドン！','スポーツ','何かを投げて、壁などに当たった',array['投','壁','当た'],2)
) v(word1,word2,category,answer,accepted_answers,difficulty)
where not exists(select 1 from question_bank where word1=v.word1 and word2=v.word2);

-- 本番公開用の追加セキュリティ設定
-- プレイ中のクライアントには正解を直接読ませず、RPC経由でオノマトペだけ返します。
create or replace function public.get_current_question(p_room_id uuid)
returns table(id uuid, word1 text, word2 text, difficulty int)
language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where rooms.id=p_room_id;
 if r.id is null then raise exception 'ルームが見つかりません'; end if;
 if not exists(select 1 from players where room_id=p_room_id and user_id=auth.uid()) then raise exception '参加者ではありません'; end if;
 return query
 select q.id,q.word1,q.word2,q.difficulty from question_bank q where q.id=r.current_question_id;
end $$;

grant execute on function public.get_current_question(uuid) to authenticated;

create or replace function public.list_my_questions()
returns table(id uuid,word1 text,word2 text,category text,answer text,accepted_answers text[],difficulty int,is_active boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
 select q.id,q.word1,q.word2,q.category,q.answer,q.accepted_answers,q.difficulty,q.is_active,q.created_at
 from question_bank q
 where q.created_by=auth.uid()
 order by q.created_at desc;
$$;
grant execute on function public.list_my_questions() to authenticated;

drop policy if exists "questions read" on public.question_bank;
create policy "questions read own" on public.question_bank for select to authenticated using (created_by=auth.uid());

-- ===== v8 追加: 結果表示と退出・ホスト移行 =====
create or replace function public.get_round_result(p_room_id uuid,p_question_no int)
returns table(answer_id uuid, answer text, correct boolean, points int, official_answer text)
language plpgsql security definer set search_path=public as $$
declare r rooms; q question_bank;
begin
  if not exists(select 1 from players where room_id=p_room_id and user_id=auth.uid()) then
    raise exception '参加者ではありません';
  end if;
  select * into r from rooms where id=p_room_id;
  if r.id is null then raise exception 'ルームが見つかりません'; end if;
  select * into q from question_bank where id=(select question_id from room_questions where room_id=p_room_id and question_no=p_question_no);
  return query
    select a.id,a.answer,a.correct,a.points,q.answer
    from round_answers a
    where a.room_id=p_room_id and a.question_no=p_question_no;
end $$;
grant execute on function public.get_round_result(uuid,int) to authenticated;

create or replace function public.leave_room(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; next_host uuid;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.id is null then return; end if;
  delete from players where room_id=p_room_id and user_id=auth.uid();
  if r.host_user_id=auth.uid() then
    select user_id into next_host from players where room_id=p_room_id order by joined_at limit 1;
    if next_host is null then
      delete from rooms where id=p_room_id;
    else
      update rooms set host_user_id=next_host where id=p_room_id;
    end if;
  end if;
end $$;
grant execute on function public.leave_room(uuid) to authenticated;

-- Realtimeを使う場合の最低限の公開設定。
-- private channel認可を厳密に行う構成へ移行する場合は realtime.messages のRLSを追加してください。
