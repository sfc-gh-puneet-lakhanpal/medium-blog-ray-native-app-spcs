USE ROLE ray_provider_role;
CREATE OR REPLACE WAREHOUSE ray_provider_wh WITH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 180
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;

CREATE DATABASE IF NOT EXISTS ray_provider_db;
use database ray_provider_db;
CREATE schema if not exists ray_provider_schema;
use schema ray_provider_schema;
CREATE IMAGE REPOSITORY if not exists ray_provider_image_repo;