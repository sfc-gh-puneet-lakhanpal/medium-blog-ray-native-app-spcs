use role ray_provider_role;
use database RAY_ON_SPCS_APP;

call ray_app_public_schema.has_app_been_initialized();

call ray_app_public_schema.get_ray_service_logs('head', 'head');
call ray_app_public_schema.get_ray_service_logs('worker', 'worker');
call ray_app_public_schema.get_ray_service_logs('custom_worker', 'ray_custom_worker');