-- Mavjud bazada bir marta ishga tushiring (1-variantga ovoz berishni serverda ham yopadi)
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
