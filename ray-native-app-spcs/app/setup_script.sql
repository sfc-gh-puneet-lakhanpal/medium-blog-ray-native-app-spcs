CREATE APPLICATION ROLE IF NOT EXISTS ray_app_role;

CREATE SCHEMA IF NOT EXISTS ray_app_core_schema;
GRANT USAGE ON SCHEMA ray_app_core_schema TO APPLICATION ROLE ray_app_role;

CREATE OR ALTER VERSIONED SCHEMA ray_app_public_schema;
GRANT USAGE ON SCHEMA ray_app_public_schema TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_service_status(service_type STRING)
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_ray_service_status'
AS
$$
from snowflake.snowpark import functions as F
def get_ray_service_status(session, service_type):
   service_name = ''
   if service_type.lower() == 'head':
      service_name = 'ray_app_core_schema.RAYHEADSERVICE'
   elif service_type.lower() == 'worker':
      service_name = 'ray_app_core_schema.RAYWORKERSERVICE'
   elif service_type.lower() == 'custom_worker':
      service_name = 'ray_app_core_schema.RAYCUSTOMWORKERSERVICE'
   else:
      return ['Please only provide one of the options: head, worker or custom worker']
   try:
      sql = f"""SELECT VALUE:status::VARCHAR as SERVICESTATUS FROM TABLE(FLATTEN(input => parse_json(system$get_service_status('{service_name}')), outer => true)) f"""
      servicestatuses = [row['SERVICESTATUS'] for row in session.sql(sql).collect()]
   except:
      servicestatuses = ['Service does not exist']
   return servicestatuses
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_service_status(STRING) TO APPLICATION ROLE ray_app_role;


CREATE OR REPLACE PROCEDURE ray_app_public_schema.has_app_been_initialized()
RETURNS BOOLEAN
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'has_app_been_initialized'
AS
$$
from snowflake.snowpark import functions as F
def has_app_been_initialized(session):
   exists = False
   try:
      result = session.table('ray_app_core_schema.APP_INITIALIZATION_TRACKER').collect()[0]['VALUE']
      if result == True:
         return True
   except:
      pass
   return exists
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.has_app_been_initialized() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.recreate_ray_compute_pool_and_service(service_type STRING, ray_head_instance_type STRING, ray_worker_instance_type STRING, ray_custom_worker_instance_type STRING, query_warehouse STRING, num_instances INTEGER)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'recreate_ray_compute_pool_and_service'
AS
$$
from snowflake.snowpark import functions as F
COMPUTE_POOL_CORES_MAPPING = {'CPU_X64_XS': 1,'CPU_X64_S': 3,'CPU_X64_M': 6,'CPU_X64_L': 28,'HIGHMEM_X64_S': 6,'HIGHMEM_X64_M': 28,'HIGHMEM_X64_L': 124,'GPU_NV_S': 6,'GPU_NV_M': 44,'GPU_NV_L': 92}
VALID_INSTANCE_TYPES = list(COMPUTE_POOL_CORES_MAPPING.keys())
COMPUTE_POOL_GPU_MAPPING = {'CPU_X64_XS': None,'CPU_X64_S': None,'CPU_X64_M': None,'CPU_X64_L': None,'HIGHMEM_X64_S': None,'HIGHMEM_X64_M': None,'HIGHMEM_X64_L': None,'GPU_NV_S': 1,'GPU_NV_M': 4,'GPU_NV_L': 8}
COMPUTE_POOL_MEMORY_MAPPING = {'CPU_X64_XS': 6,'CPU_X64_S': 13,'CPU_X64_M': 28,'CPU_X64_L': 116,'HIGHMEM_X64_S': 58,'HIGHMEM_X64_M': 240,'HIGHMEM_X64_L': 984,'GPU_NV_S': 27,'GPU_NV_M': 178,'GPU_NV_L': 1112}
CPU_CONSTANT = 'CPU'
GPU_CONSTANT = 'GPU'
HIGH_MEM_CONSTANT = 'HIGH_MEM'
INSTANCE_TYPE_MAPPING = {'CPU_X64_XS': CPU_CONSTANT,'CPU_X64_S': CPU_CONSTANT,'CPU_X64_M': CPU_CONSTANT,'CPU_X64_L': CPU_CONSTANT,'HIGHMEM_X64_S': CPU_CONSTANT,'HIGHMEM_X64_M': CPU_CONSTANT,'HIGHMEM_X64_L': CPU_CONSTANT,'GPU_NV_S': GPU_CONSTANT,'GPU_NV_M': GPU_CONSTANT,'GPU_NV_L': GPU_CONSTANT}
DHSM_MEMORY_FACTOR = 0.1
INSTANCE_AVAILABLE_MEMORY_FOR_RAY_FACTOR = 0.8
MIN_DSHM_MEMORY = 11
SNOW_OBJECT_IDENTIFIER_MAX_LENGTH = 255
CP_OBJECT_IDENTIFIER_MAX_LENGTH=63
def execute_sql(session, sql):
   _ = session.sql(sql).collect()
def get_valid_object_identifier_name(name:str, object_type:str="cp"):
   result = ""
   if object_type.lower() == 'cp':
      result = str(name).upper()[0:CP_OBJECT_IDENTIFIER_MAX_LENGTH-1]
   else:
	   result = str(name).upper()[0:SNOW_OBJECT_IDENTIFIER_MAX_LENGTH-1]
   return result
def get_query_warehouse_config(session, query_warehouse):
   config = {}
   if query_warehouse=='XS':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'XSMALL'
   elif query_warehouse=='S':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'SMALL'
   elif query_warehouse=='M':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'MEDIUM'
   elif query_warehouse=='L':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'LARGE'
   elif query_warehouse=='XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'XLARGE'
   elif query_warehouse=='2XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'XXLARGE'
   elif query_warehouse=='3XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'XXXLARGE'
   elif query_warehouse=='4XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'X4LARGE'
   elif query_warehouse=='5XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'X5LARGE'
   elif query_warehouse=='6XL':
      config['WAREHOUSE_TYPE'] = 'STANDARD'
      config['WAREHOUSE_SIZE'] = 'X6LARGE'
   elif query_warehouse=='MSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'MEDIUM'
   elif query_warehouse=='LSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'LARGE'
   elif query_warehouse=='XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'XLARGE'
   elif query_warehouse=='2XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'XXLARGE'
   elif query_warehouse=='3XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'XXXLARGE'
   elif query_warehouse=='4XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'X4LARGE'
   elif query_warehouse=='5XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'X5LARGE'
   elif query_warehouse=='6XLSOW':
      config['WAREHOUSE_TYPE'] = 'SNOWPARK-OPTIMIZED'
      config['WAREHOUSE_SIZE'] = 'X6LARGE'
   return config
def generate_spec_for_ray_head(session, ray_head_cp_type, dshm_memory_for_ray_head, instance_available_memory_for_ray_head, gpus_available_for_ray_head):
   if ray_head_cp_type=='GPU':
      ray_head_spec_def = f"""
spec:
   containers:
   -  name: head
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_head
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: raylogs
         mountPath: /raylogs
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         ENV_RAY_GRAFANA_HOST: http://rayheadservice.ray-app-core-schema:3000
         ENV_RAY_PROMETHEUS_HOST: http://rayheadservice.ray-app-core-schema:9090
         AUTOSCALER_METRIC_PORT: '8083'
         DASHBOARD_METRIC_PORT: '8084'
      resources:
         limits:
            nvidia.com/gpu: {gpus_available_for_ray_head}
         requests:
            nvidia.com/gpu: {gpus_available_for_ray_head}
   -  name: prometheus
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_prometheus
      volumeMounts:
      -  name: raylogs
         mountPath: /raylogs
   -  name: grafana
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_grafana
      volumeMounts:
      -  name: raylogs
         mountPath: /raylogs
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_head}
   -  name: raylogs
      source: block
      size: 20Gi
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: api
      port: 8000
      public: true
   -  name: notebook
      port: 8888
      public: true
   -  name: ray-gcs-server-port
      port: 6379
      protocol: TCP
      public: false
   -  name: ray-client-server-port
      port: 10001
      public: false
   -  name: prometheus
      port: 9090
      public: true
   -  name: grafana
      port: 3000
      public: true
   -  name: ray-dashboard
      port: 8265
      public: true
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: autoscaler-metric-port
      port: 8083
      protocol: TCP
      public: false
   -  name: dashboard-metric-port
      port: 8084
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
   """
   else:
      ray_head_spec_def = f"""
spec:
   containers:
   -  name: head
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_head
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: raylogs
         mountPath: /raylogs
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         ENV_RAY_GRAFANA_HOST: http://rayheadservice.ray-app-core-schema:3000
         ENV_RAY_PROMETHEUS_HOST: http://rayheadservice.ray-app-core-schema:9090
         AUTOSCALER_METRIC_PORT: '8083'
         DASHBOARD_METRIC_PORT: '8084'
      resources:
         requests:
            memory: "{instance_available_memory_for_ray_head}"
   -  name: prometheus
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_prometheus
      volumeMounts:
      -  name: raylogs
         mountPath: /raylogs
   -  name: grafana
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_grafana
      volumeMounts:
      -  name: raylogs
         mountPath: /raylogs
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_head}
   -  name: raylogs
      source: block
      size: 20Gi
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: api
      port: 8000
      public: true
   -  name: notebook
      port: 8888
      public: true
   -  name: ray-gcs-server-port
      port: 6379
      protocol: TCP
      public: false
   -  name: ray-client-server-port
      port: 10001
      public: true
   -  name: prometheus
      port: 9090
      public: true
   -  name: grafana
      port: 3000
      public: true
   -  name: ray-dashboard
      port: 8265
      public: true
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: autoscaler-metric-port
      port: 8083
      protocol: TCP
      public: false
   -  name: dashboard-metric-port
      port: 8084
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
   """
   return ray_head_spec_def
def generate_spec_for_ray_worker(session, ray_worker_cp_type, num_ray_workers, dshm_memory_for_ray_worker, gpus_available_for_ray_worker, instance_available_memory_for_ray_worker):
   ray_worker_spec_def = ""
   if num_ray_workers>0:
      if ray_worker_cp_type=='GPU':
         ray_worker_spec_def = f"""
spec:
   containers:
   -  name: worker
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_worker
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         RAY_HEAD_ADDRESS: rayheadservice.ray-app-core-schema:6379
      resources:
         limits:
            nvidia.com/gpu: {gpus_available_for_ray_worker}
         requests:
            nvidia.com/gpu: {gpus_available_for_ray_worker}
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_worker}
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
      """
      else:
         ray_worker_spec_def = f"""
spec:
   containers:
   -  name: worker
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_worker
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         RAY_HEAD_ADDRESS: rayheadservice.ray-app-core-schema:6379
      resources:
         requests:
            memory: "{instance_available_memory_for_ray_worker}"
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_worker}
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
      """
   return ray_worker_spec_def
def generate_spec_for_ray_custom_worker(session, ray_custom_worker_cp_type, num_ray_custom_workers, dshm_memory_for_ray_worker, gpus_available_for_ray_worker, instance_available_memory_for_ray_worker):
   ray_custom_worker_spec_def = ""
   if num_ray_custom_workers>0:
      if ray_custom_worker_cp_type=='GPU':
         ray_custom_worker_spec_def = f"""
spec:
   containers:
   -  name: worker
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_custom_worker
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         RAY_HEAD_ADDRESS: rayheadservice.ray-app-core-schema:6379
      resources:
         limits:
            nvidia.com/gpu: {gpus_available_for_ray_worker}
         requests:
            nvidia.com/gpu: {gpus_available_for_ray_worker}
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_worker}
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
      """
      else:
         ray_custom_worker_spec_def = f"""
spec:
   containers:
   -  name: worker
      image: /ray_provider_db/ray_provider_schema/ray_provider_image_repo/native_app_ray_custom_worker
      volumeMounts:
      -  name: dshm
         mountPath: /dev/shm
      -  name: artifacts
         mountPath: /home/artifacts
      env:
         RAY_HEAD_ADDRESS: rayheadservice.ray-app-core-schema:6379
      resources:
         requests:
            memory: "{instance_available_memory_for_ray_worker}"
   volumes:
   -  name: dshm
      source: memory
      size: {dshm_memory_for_ray_worker}
   -  name: artifacts
      source: '@ray_app_public_schema.ARTIFACTS'
   endpoints:
   -  name: object-manager-port
      port: 8076
      protocol: TCP
      public: false
   -  name: node-manager-port
      port: 8077
      protocol: TCP
      public: false
   -  name: dashboard-agent-grpc-port
      port: 8079
      protocol: TCP
      public: false
   -  name: dashboard-agent-listen-port
      port: 8081
      protocol: TCP
      public: false
   -  name: metrics-export-port
      port: 8082
      protocol: TCP
      public: false
   -  name: worker-ports
      portRange: 10002-19999
      protocol: TCP
   -  name: ephemeral-port-range
      portRange: 32768-60999
      protocol: TCP
      """
   return ray_custom_worker_spec_def
def create_service(session, service_type, service_name, cp_name, ray_head_instance_type, ray_worker_instance_type, ray_custom_worker_instance_type, num_instances, query_warehouse_name):
   if num_instances>0:
      entry_name = ''
      cp_type = ''
      cpu_or_gpu = ''
      ray_num_instances = 0
      if service_type.lower() == 'head':
         entry_name = 'RAY_HEAD'
         cp_type = ray_head_instance_type
         cpu_or_gpu = INSTANCE_TYPE_MAPPING[ray_head_instance_type]
         ray_num_instances = 1
      elif service_type.lower() == 'worker':
         entry_name = 'RAY_WORKER'
         cp_type = ray_worker_instance_type
         cpu_or_gpu = INSTANCE_TYPE_MAPPING[ray_worker_instance_type]
         ray_num_instances = num_instances
      elif service_type.lower() == 'custom_worker':
         entry_name = 'RAY_CUSTOM_WORKER'
         cp_type = ray_custom_worker_instance_type
         cpu_or_gpu = INSTANCE_TYPE_MAPPING[ray_custom_worker_instance_type]
         ray_num_instances = num_instances
      else:
         return ['Please only provide one of the options: head, worker or custom_worker']
      create_specs_sql = "CREATE TABLE IF NOT EXISTS ray_app_core_schema.YAML (name varchar, value varchar)"
      execute_sql(session, create_specs_sql)
      ray_service_spec = ''
      if service_type.lower() == 'head':
         instance_available_memory_for_ray_head = str(int(INSTANCE_AVAILABLE_MEMORY_FOR_RAY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])) + 'G'
         dshm = int(DHSM_MEMORY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])
         if dshm < MIN_DSHM_MEMORY:
            dshm = MIN_DSHM_MEMORY
         dshm_memory_for_ray_head = str(MIN_DSHM_MEMORY) + 'Gi'
         gpus_available_for_ray_head = COMPUTE_POOL_GPU_MAPPING[cp_type]
         num_head_cores = COMPUTE_POOL_CORES_MAPPING[cp_type]
         ray_service_spec = generate_spec_for_ray_head(session, cpu_or_gpu, dshm_memory_for_ray_head, instance_available_memory_for_ray_head, gpus_available_for_ray_head)
         delete_prior_service_spec_sql = "DELETE FROM ray_app_core_schema.YAML where NAME = 'RAY_HEAD'"
         execute_sql(session, delete_prior_service_spec_sql)
         ray_head_snow_df = session.create_dataframe([['RAY_HEAD', ray_service_spec]], schema=["NAME", "VALUE"])
         ray_head_snow_df.write.save_as_table("ray_app_core_schema.YAML", mode="append")
      elif service_type.lower() == 'worker':
         instance_available_memory_for_ray_worker = str(int(INSTANCE_AVAILABLE_MEMORY_FOR_RAY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])) + 'G'
         dshm = int(DHSM_MEMORY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])
         if dshm < MIN_DSHM_MEMORY:
               dshm = MIN_DSHM_MEMORY
         dshm_memory_for_ray_worker = str(MIN_DSHM_MEMORY) + 'Gi'   
         gpus_available_for_ray_worker = COMPUTE_POOL_GPU_MAPPING[cp_type]
         num_worker_cores = COMPUTE_POOL_CORES_MAPPING[cp_type]
         ray_service_spec = generate_spec_for_ray_worker(session, cpu_or_gpu, num_instances, dshm_memory_for_ray_worker, gpus_available_for_ray_worker, instance_available_memory_for_ray_worker)
         delete_prior_service_spec_sql = "DELETE FROM ray_app_core_schema.YAML where NAME = 'RAY_WORKER'"
         execute_sql(session, delete_prior_service_spec_sql)
         ray_worker_snow_df = session.create_dataframe([['RAY_WORKER', ray_service_spec]], schema=["NAME", "VALUE"])
         ray_worker_snow_df.write.save_as_table("ray_app_core_schema.YAML", mode="append")
      elif service_type.lower() == 'custom_worker':
         instance_available_memory_for_ray_worker = str(int(INSTANCE_AVAILABLE_MEMORY_FOR_RAY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])) + 'G'
         dshm = int(DHSM_MEMORY_FACTOR * COMPUTE_POOL_MEMORY_MAPPING[cp_type])
         if dshm < MIN_DSHM_MEMORY:
               dshm = MIN_DSHM_MEMORY
         dshm_memory_for_ray_worker = str(MIN_DSHM_MEMORY) + 'Gi'   
         gpus_available_for_ray_worker = COMPUTE_POOL_GPU_MAPPING[cp_type]
         num_worker_cores = COMPUTE_POOL_CORES_MAPPING[cp_type]
         ray_service_spec = generate_spec_for_ray_custom_worker(session, cpu_or_gpu, num_instances, dshm_memory_for_ray_worker, gpus_available_for_ray_worker, instance_available_memory_for_ray_worker)
         delete_prior_service_spec_sql = "DELETE FROM ray_app_core_schema.YAML where NAME = 'RAY_CUSTOM_WORKER'"
         execute_sql(session, delete_prior_service_spec_sql)
         ray_custom_worker_snow_df = session.create_dataframe([['RAY_CUSTOM_WORKER', ray_service_spec]], schema=["NAME", "VALUE"])
         ray_custom_worker_snow_df.write.save_as_table("ray_app_core_schema.YAML", mode="append")
      create_service_sql = f"""CREATE SERVICE {service_name}
      IN COMPUTE POOL {cp_name}
      FROM SPECIFICATION 
      {chr(36)}{chr(36)}
      {ray_service_spec}
      {chr(36)}{chr(36)}
      MIN_INSTANCES={ray_num_instances}
      MAX_INSTANCES={ray_num_instances}
      EXTERNAL_ACCESS_INTEGRATIONS = (reference('external_access_reference'))
      QUERY_WAREHOUSE={query_warehouse_name}
      """
      execute_sql(session, create_service_sql)
      return "SUCCESS"
   else:
      return "NO SERVICE CREATED"
def is_app_initialized(session):
   try:
      result = session.table("ray_app_core_schema.APP_INITIALIZATION_TRACKER").collect()[0]['VALUE']
      if result == True: 
         return True
   except:
      pass
   return False
def initialize_artifacts(session, query_warehouse_type, query_warehouse_name):
   #create artifacts once
   sql1 = """create stage if not exists ray_app_public_schema.ARTIFACTS ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE') DIRECTORY = (ENABLE = TRUE)"""
   sql2 = """create stage if not exists ray_app_core_schema.RAYLOGS ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE') DIRECTORY = (ENABLE = TRUE)"""
   sql3 = """GRANT READ, WRITE ON STAGE ray_app_public_schema.ARTIFACTS TO APPLICATION ROLE ray_app_role"""
   sql4 = """GRANT READ, WRITE ON STAGE ray_app_core_schema.RAYLOGS TO APPLICATION ROLE ray_app_role"""
   execute_sql(session, sql1)
   execute_sql(session, sql2)
   execute_sql(session, sql3)
   execute_sql(session, sql4)   
   query_warehouse_config = get_query_warehouse_config(session, query_warehouse_type)
   warehouse_size = query_warehouse_config['WAREHOUSE_SIZE']
   warehouse_type = query_warehouse_config['WAREHOUSE_TYPE']
   create_warehouse_sql = f"create or replace warehouse {query_warehouse_name} WAREHOUSE_SIZE={warehouse_size} WAREHOUSE_TYPE={warehouse_type} INITIALLY_SUSPENDED=TRUE AUTO_RESUME=TRUE"
   execute_sql(session, create_warehouse_sql)
   #initialize app
   initialize_app_sql = "CREATE OR REPLACE TABLE ray_app_core_schema.APP_INITIALIZATION_TRACKER (VALUE boolean)"
   execute_sql(session, initialize_app_sql)
   app_initialization_df = session.create_dataframe([[True]], schema=["VALUE"])
   app_initialization_df.write.save_as_table("ray_app_core_schema.APP_INITIALIZATION_TRACKER", mode="append")
   ray_config_sql = "CREATE OR REPLACE TABLE ray_app_core_schema.RAY_CONFIG (cp_type varchar, instance_name varchar, num_instances integer, query_warehouse varchar)"
   execute_sql(session, ray_config_sql)
def get_ray_cluster_config_per_service(session, service_type):
   cp_type = ''
   if service_type.lower() == 'head':
      cp_type = 'RAY_HEAD'
   elif service_type.lower() == 'worker':
      cp_type = 'RAY_WORKER'
   elif service_type.lower() == 'custom_worker':
      cp_type = 'RAY_CUSTOM_WORKER'
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   ray_cluster_config = {}
   try:
      ray_conf_snowdf = session.table('ray_app_core_schema.RAY_CONFIG')
      ray_conf = ray_conf_snowdf.filter(ray_conf_snowdf['CP_TYPE']==cp_type).collect()[0]
      ray_cluster_config["cp_type"] = cp_type
      ray_cluster_config["instance_name"] = ray_conf['INSTANCE_NAME']
      ray_cluster_config["num_instances"] = ray_conf['NUM_INSTANCES']
      ray_cluster_config["query_warehouse"] = ray_conf['QUERY_WAREHOUSE']
   except:
      pass
   return ray_cluster_config
def does_the_service_exist_already(session, service_type, instance_name, num_instances, query_warehouse):
   cp_type = ''
   if service_type.lower() == 'head':
      cp_type = 'RAY_HEAD'
   elif service_type.lower() == 'worker':
      cp_type = 'RAY_WORKER'
   elif service_type.lower() == 'custom_worker':
      cp_type = 'RAY_CUSTOM_WORKER'
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   service_exists_already = False
   proposed_ray_cluster_config = {"cp_type": cp_type, "instance_name": instance_name, "num_instances": num_instances, "query_warehouse": query_warehouse}
   ray_cluster_config_for_service = get_ray_cluster_config_per_service(session, service_type)
   len_ray_cluster_config_for_service = len(ray_cluster_config_for_service)
   if (proposed_ray_cluster_config==ray_cluster_config_for_service):
      service_exists_already = True
   return service_exists_already
def generate_ray_config_per_service(session, service_type, instance_name, query_warehouse, num_instances):
   cp_type = ''
   if service_type.lower() == 'head':
      cp_type = 'RAY_HEAD'
   elif service_type.lower() == 'worker':
      cp_type = 'RAY_WORKER'
   elif service_type.lower() == 'custom_worker':
      cp_type = 'RAY_CUSTOM_WORKER'
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   snow_df = session.create_dataframe([[cp_type, instance_name, num_instances, query_warehouse]], schema=["CP_TYPE", "INSTANCE_NAME", "NUM_INSTANCES", "QUERY_WAREHOUSE"])
   snow_df.write.save_as_table("ray_app_core_schema.RAY_CONFIG", mode="append")
def recreate_ray_compute_pool_and_service(session, service_type, ray_head_instance_type, ray_worker_instance_type, ray_custom_worker_instance_type, query_warehouse, num_instances):
   if (ray_head_instance_type.upper() not in VALID_INSTANCE_TYPES) or (ray_worker_instance_type.upper() not in VALID_INSTANCE_TYPES) or (ray_custom_worker_instance_type.upper() not in VALID_INSTANCE_TYPES):
      return f"Invalid value provided for instance_types: {ray_head_instance_type}, {ray_worker_instance_type}, {ray_custom_worker_instance_type}"
   if num_instances<0:
      return f"Invalid value provided for num_instances: {num_instances}. Must be >=0"
   service_name = ''
   cp_name = ''
   ray_instance_type = ''
   ray_num_instances = 0
   current_database = session.get_current_database().replace('"', '')
   query_warehouse_name = get_valid_object_identifier_name(f"{current_database}_ray_query_warehouse")
   if service_type.lower() == 'head':
      service_name = 'ray_app_core_schema.RAYHEADSERVICE'
      cp_name = f"{current_database}_ray_head_cp"
      ray_instance_type = ray_head_instance_type
      ray_num_instances = 1
   elif service_type.lower() == 'worker':
      service_name = 'ray_app_core_schema.RAYWORKERSERVICE'
      cp_name = f"{current_database}_ray_worker_cp"
      ray_instance_type = ray_worker_instance_type
      ray_num_instances = num_instances
   elif service_type.lower() == 'custom_worker':
      service_name = 'ray_app_core_schema.RAYCUSTOMWORKERSERVICE'
      cp_name = f"{current_database}_ray_custom_worker_cp"
      ray_instance_type = ray_custom_worker_instance_type
      ray_num_instances = num_instances
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   cp_name = get_valid_object_identifier_name(cp_name)
   if not is_app_initialized(session):
      initialize_artifacts(session, query_warehouse, query_warehouse_name)
   does_the_service_exist_already_response = does_the_service_exist_already(session, service_type, ray_instance_type, ray_num_instances, query_warehouse)
   if not does_the_service_exist_already_response:
      session.sql(f"alter compute pool IF EXISTS {cp_name} stop all").collect()
      session.sql(f"drop compute pool IF EXISTS {cp_name}").collect()
      if ray_num_instances > 0:
         sql = f"""CREATE COMPUTE POOL {cp_name}
         MIN_NODES = {ray_num_instances}
         MAX_NODES = {ray_num_instances}
         INSTANCE_FAMILY = {ray_instance_type}
         AUTO_RESUME = true
         AUTO_SUSPEND_SECS = 3600
         """
         session.sql(sql).collect()
         create_service(session, service_type, service_name, cp_name, ray_head_instance_type, ray_worker_instance_type, ray_custom_worker_instance_type, ray_num_instances, query_warehouse_name)
         generate_ray_config_per_service(session, service_type, ray_instance_type, query_warehouse, ray_num_instances)
         execute_sql(session, f"GRANT USAGE ON SERVICE {service_name} TO APPLICATION ROLE ray_app_role")
         execute_sql(session, f"GRANT MONITOR ON SERVICE {service_name} TO APPLICATION ROLE ray_app_role")
         execute_sql(session, f"GRANT SERVICE ROLE {service_name}!ALL_ENDPOINTS_USAGE TO APPLICATION ROLE ray_app_role")
      return f"SUCCESS"
   else:
      return "NO CHANGES MADE TO THE SERVICE"
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.recreate_ray_compute_pool_and_service(STRING, STRING, STRING, STRING, STRING, INTEGER) TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_service_specs()
RETURNS TABLE(NAME VARCHAR, VALUE VARCHAR)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_ray_service_specs'
AS
$$
def get_ray_service_specs(session):
   ray_conf_snowdf = session.table('ray_app_core_schema.YAML')
   return ray_conf_snowdf
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_service_specs() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_service_status_with_message(service_type STRING)
RETURNS TABLE(SERVICESTATUS VARCHAR, SERVICEMESSAGE VARCHAR)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_ray_service_status_with_message'
AS
$$
from snowflake.snowpark import functions as F
def get_ray_service_status_with_message(session, service_type):
   if service_type.lower() == 'head':
      service_name = 'ray_app_core_schema.RAYHEADSERVICE'
   elif service_type.lower() == 'worker':
      service_name = 'ray_app_core_schema.RAYWORKERSERVICE'
   elif service_type.lower() == 'custom_worker':
      service_name = 'ray_app_core_schema.RAYCUSTOMWORKERSERVICE'
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   sql = f"SELECT VALUE:status::VARCHAR as SERVICESTATUS, VALUE:message::VARCHAR as SERVICEMESSAGE FROM TABLE(FLATTEN(input => parse_json(system$get_service_status('{service_name}')), outer => true)) f"
   snowdf = session.sql(sql)
   return snowdf
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_service_status_with_message(STRING) TO APPLICATION ROLE ray_app_role;



CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_public_endpoints()
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_all_endpoints'
AS
$$
def get_public_endpoints_by_service_name(session, service_name):
   public_endpoints = []
   rows = 0
   try:
      rows = session.sql(f'SHOW ENDPOINTS IN SERVICE {service_name}').collect()
   except:
      return public_endpoints
   ingress_urls = [row['ingress_url'] for row in rows]
   ingress_enabled = [row['is_public'] for row in rows]
   if any(ispublic == 'true' for ispublic in ingress_enabled) and any(url=='Endpoints provisioning in progress... check back in a few minutes' for url in ingress_urls):
      endpoint = {}
      service_name_shorted = str(service_name.split('.')[1]).lower()
      endpoint[service_name_shorted] = 'Endpoints provisioning in progress... check back in a few minutes'
      public_endpoints.append(endpoint)
      return public_endpoints
   for row in rows:
      if row['is_public'] == 'true':
         endpoint = {}
         endpoint[row['name']] = row['ingress_url']
         public_endpoints.append(endpoint)
   return public_endpoints
def get_all_endpoints(session):
   public_endpoints = []
   ray_head_public_endpoints = get_public_endpoints_by_service_name(session, 'ray_app_core_schema.RAYHEADSERVICE')
   ray_worker_public_endpoints = get_public_endpoints_by_service_name(session, 'ray_app_core_schema.RAYWORKERSERVICE')
   ray_custom_worker_public_endpoints = get_public_endpoints_by_service_name(session, 'ray_app_core_schema.RAYCUSTOMWORKERSERVICE')
   if len(ray_head_public_endpoints)>0:
      public_endpoints.append(ray_head_public_endpoints)
   if len(ray_worker_public_endpoints)>0:
      public_endpoints.append(ray_worker_public_endpoints)
   if len(ray_custom_worker_public_endpoints)>0:
      public_endpoints.append(ray_custom_worker_public_endpoints)
   return public_endpoints
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_public_endpoints() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.delete_ray_cluster()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'delete_ray_cluster'
AS
$$
SNOW_OBJECT_IDENTIFIER_MAX_LENGTH = 255
CP_OBJECT_IDENTIFIER_MAX_LENGTH=63
def execute_sql(session, sql):
   _ = session.sql(sql).collect()
def get_valid_object_identifier_name(name:str, object_type:str="cp"):
   result = ""
   if object_type.lower() == 'cp':
      result = str(name).upper()[0:CP_OBJECT_IDENTIFIER_MAX_LENGTH-1]
   else:
	   result = str(name).upper()[0:SNOW_OBJECT_IDENTIFIER_MAX_LENGTH-1]
   return result
def delete_ray_cluster(session):
   current_database = session.get_current_database().replace('"', '')
   ray_head_cp_name = get_valid_object_identifier_name(f"{current_database}_ray_head_cp")
   ray_worker_cp_name = get_valid_object_identifier_name(f"{current_database}_ray_worker_cp")
   ray_custom_worker_cp_name = get_valid_object_identifier_name(f"{current_database}_ray_custom_worker_cp")
   query_warehouse_name = get_valid_object_identifier_name(f"{current_database}_ray_query_warehouse")
   ray_specs_table_name = "ray_app_core_schema.YAML"
   execute_sql(session, f"alter compute pool if exists {ray_head_cp_name} stop all")
   execute_sql(session, f"alter compute pool if exists {ray_worker_cp_name} stop all")
   execute_sql(session, f"alter compute pool if exists {ray_custom_worker_cp_name} stop all")
   execute_sql(session, f"drop compute pool if exists {ray_head_cp_name}")
   execute_sql(session, f"drop compute pool if exists {ray_worker_cp_name}")
   execute_sql(session, f"drop compute pool if exists {ray_custom_worker_cp_name}")
   execute_sql(session, f"drop table if exists {ray_specs_table_name}")
   execute_sql(session, f"drop warehouse if exists {query_warehouse_name}")
   delete_prior_app_initialization_sql = "DELETE FROM ray_app_core_schema.APP_INITIALIZATION_TRACKER where 1=1"
   _ = session.sql(delete_prior_app_initialization_sql).collect()
   app_initialization_df = session.create_dataframe([[False]], schema=["VALUE"])
   app_initialization_df.write.save_as_table("ray_app_core_schema.APP_INITIALIZATION_TRACKER", mode="append")
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.delete_ray_cluster() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_cluster_config()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_ray_cluster_config'
AS
$$
def get_ray_cluster_config(session):
   ray_cluster_config = {}
   try:
      ray_conf_snowdf = session.table('ray_app_core_schema.RAY_CONFIG')
      ray_head_conf = ray_conf_snowdf.filter(ray_conf_snowdf['CP_TYPE']=='RAY_HEAD').collect()[0]
      ray_head_instance_family = ray_head_conf['INSTANCE_NAME']
      ray_query_warehouse = ray_head_conf['QUERY_WAREHOUSE']
      ray_cluster_config['ray_head'] = ray_head_instance_family
      ray_cluster_config['query_warehouse'] = ray_query_warehouse
      try:
         ray_worker_conf_results = ray_conf_snowdf.filter(ray_conf_snowdf['CP_TYPE']=='RAY_WORKER').collect()
         ray_worker_conf = ray_worker_conf_results[0]
         ray_worker_instance_family = ray_worker_conf['INSTANCE_NAME']
         ray_worker_num_instances = ray_worker_conf['NUM_INSTANCES']
         ray_cluster_config['ray_worker'] = [ray_worker_instance_family, ray_worker_num_instances]
      except:
         pass
      try:
         ray_custom_worker_conf_results = ray_conf_snowdf.filter(ray_conf_snowdf['CP_TYPE']=='RAY_CUSTOM_WORKER').collect()
         ray_custom_worker_conf = ray_custom_worker_conf_results[0]
         ray_custom_worker_instance_family = ray_custom_worker_conf['INSTANCE_NAME']
         ray_custom_worker_num_instances = ray_custom_worker_conf['NUM_INSTANCES']
         ray_cluster_config['ray_custom_worker'] = [ray_custom_worker_instance_family, ray_custom_worker_num_instances]
      except:
         pass
   except:
      pass
   return ray_cluster_config
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_cluster_config() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.show_ray_cluster_config_contents()
RETURNS TABLE(cp_type varchar, instance_name varchar, num_instances integer, query_warehouse varchar)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'show_ray_cluster_config_contents'
AS
$$
def show_ray_cluster_config_contents(session):
   snowdf = session.table('ray_app_core_schema.RAY_CONFIG')
   return snowdf
$$;

GRANT USAGE ON PROCEDURE ray_app_public_schema.show_ray_cluster_config_contents() TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE PROCEDURE ray_app_public_schema.get_ray_service_logs(service_type STRING, container_name STRING)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'get_ray_service_logs'
AS
$$
from snowflake.snowpark import functions as F
def get_ray_service_logs(session, service_type, container_name):
   service_name = ''
   if service_type.lower() == 'head':
      service_name = 'ray_app_core_schema.RAYHEADSERVICE'
   elif service_type.lower() == 'worker':
      service_name = 'ray_app_core_schema.RAYWORKERSERVICE'
   elif service_type.lower() == 'custom_worker':
      service_name = 'ray_app_core_schema.RAYCUSTOMWORKERSERVICE'
   else:
      return ['Please only provide one of the options: head, worker or custom_worker']
   try:
      sql1 = f"""SELECT VALUE:status::VARCHAR as SERVICESTATUS FROM TABLE(FLATTEN(input => parse_json(system$get_service_status('{service_name}')), outer => true)) f"""
      servicestatuses = [row['SERVICESTATUS'] for row in session.sql(sql1).collect()]
      if any(status == 'PENDING' for status in servicestatuses):
         return "Logs unavailable since service is in pending status"
      sql2 = f"""select system$GET_SERVICE_LOGS('{service_name}', 0, '{container_name}', 1000) as LOG"""
      return session.sql(sql2).collect()[0]['LOG']
   except:
      return "Service does not exist"
$$;
GRANT USAGE ON PROCEDURE ray_app_public_schema.get_ray_service_logs(STRING, STRING) TO APPLICATION ROLE ray_app_role;

-- Create callbacks called in the manifest.yml
CREATE OR REPLACE PROCEDURE ray_app_core_schema.register_single_callback(ref_name STRING, operation STRING, ref_or_alias STRING)
RETURNS STRING
LANGUAGE SQL
AS 
$$
  BEGIN
    CASE (operation)
      WHEN 'ADD' THEN
        SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
      WHEN 'REMOVE' THEN
        SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
      WHEN 'CLEAR' THEN
        SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
    ELSE
      RETURN 'unknown operation: ' || operation;
    END CASE;
  END;
$$;

GRANT USAGE ON PROCEDURE ray_app_core_schema.register_single_callback(STRING, STRING, STRING) TO APPLICATION ROLE ray_app_role;

-- Configuration callback for the `EXTERNAL_ACCESS_REFERENCE` defined in the manifest.yml
-- The procedure returns a json format object containing information about the EAI to be created, that is
-- and show the same information in a popup-window in the UI.
-- There are no allowed_secrets since the API doesn't require authentication.
CREATE OR REPLACE PROCEDURE ray_app_core_schema.get_configuration(ref_name STRING)
RETURNS STRING
LANGUAGE SQL
AS 
$$
BEGIN
  CASE (UPPER(ref_name))
      WHEN 'EXTERNAL_ACCESS_REFERENCE' THEN
          RETURN OBJECT_CONSTRUCT(
              'type', 'CONFIGURATION',
              'payload', OBJECT_CONSTRUCT(
                  'host_ports', ARRAY_CONSTRUCT('0.0.0.0:443','0.0.0.0:80'),
                  'allowed_secrets', 'NONE')
          )::STRING;
      ELSE
          RETURN '';
  END CASE;
END;	
$$;

GRANT USAGE ON PROCEDURE ray_app_core_schema.get_configuration(STRING) TO APPLICATION ROLE ray_app_role;

CREATE OR REPLACE STREAMLIT ray_app_public_schema.ray_config_streamlit_app
     FROM '/code_artifacts/streamlit'
     MAIN_FILE = '/streamlit_app.py';

GRANT USAGE ON SCHEMA ray_app_public_schema TO APPLICATION ROLE ray_app_role;
GRANT USAGE ON STREAMLIT ray_app_public_schema.ray_config_streamlit_app TO APPLICATION ROLE ray_app_role;


-- The rest of this script is left blank for purposes of your learning and exploration. 
