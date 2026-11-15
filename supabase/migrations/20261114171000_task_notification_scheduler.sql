-- Durable delivery even when the app closes before its wake-up request finishes.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$ begin
 if not exists(select 1 from vault.secrets where name='emville_task_notification_secret') then
 perform vault.create_secret(gen_random_uuid()::text||gen_random_uuid()::text,
   'emville_task_notification_secret','Private authentication for task notification delivery');
 end if;
end $$;

-- Called only by the service-role Edge function. The private secret never leaves
-- the database except as an HTTPS header on its scheduled invocation.
create or replace function public.validate_task_scheduler_secret(p_secret text)
returns boolean language sql stable security definer set search_path=public,vault as $$
 select coalesce(length(p_secret)>0 and p_secret=(select decrypted_secret from vault.decrypted_secrets
   where name='emville_task_notification_secret' limit 1),false)
$$;
revoke all on function public.validate_task_scheduler_secret(text) from public,anon,authenticated;
grant execute on function public.validate_task_scheduler_secret(text) to service_role;

do $$ begin
 if exists(select 1 from cron.job where jobname='emville-task-notification-delivery') then
 perform cron.unschedule('emville-task-notification-delivery');
 end if;
 perform cron.schedule('emville-task-notification-delivery','* * * * *',$job$
   select net.http_post(
     url := 'https://qcqalhmwawesewphvdrq.supabase.co/functions/v1/task_notifications',
     headers := jsonb_build_object('Content-Type','application/json','x-task-secret',
       (select decrypted_secret from vault.decrypted_secrets where name='emville_task_notification_secret' limit 1)),
     body := '{}'::jsonb,
     timeout_milliseconds := 10000
   );
 $job$);
end $$;
