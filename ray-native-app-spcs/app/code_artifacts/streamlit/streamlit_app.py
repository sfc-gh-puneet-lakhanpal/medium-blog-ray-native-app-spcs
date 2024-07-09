import streamlit as st
st.set_page_config(layout="wide")
from dataclasses import dataclass
from snowflake.snowpark.context import get_active_session
import snowflake.permissions as permission
from snowflake.snowpark.functions import call_udf, lit
import json
session = get_active_session()
instance_type_dict = {
    'CPU_X64_XS': 0, 
    'CPU_X64_S': 1, 
    'CPU_X64_M': 2, 
    'CPU_X64_L': 3, 
    'HIGHMEM_X64_S': 4, 
    'HIGHMEM_X64_M': 5, 
    'HIGHMEM_X64_L': 6, 
    'GPU_NV_S': 7, 
    'GPU_NV_M': 8, 
    'GPU_NV_L': 9
    }
warehouse_type_dict = {
    'XS': 0,
    'S': 1,
    'M': 2,
    'L': 3,
    'XL': 4,
    '2XL': 5,
    '3XL': 6,
    '4XL': 7,
    '5XL': 8,
    '6XL': 9,
    'MSOW': 10,
    'LSOW': 11,
    'XLSOW': 12,
    '2XLSOW': 13,
    '3XLSOW': 14,
    '4XLSOW': 15,
    '5XLSOW': 16,
    '6XLSOW': 17  
}
instance_types = list(instance_type_dict.keys())
warehouse_types = list(warehouse_type_dict.keys())
current_database = session.get_current_database().replace('"', '')
@dataclass
class Reference:
    name: str
    label: str
    type: str
    description: str
    bound_alias: str
def setup():
    refs = get_references()
    for ref in refs:
        name = ref.name
        label = ref.label
        if not ref.bound_alias:
            st.header("First-time setup")
            st.caption("""
            Follow the instructions below to set up your application.
            Once you have completed the steps, you will be able to continue to the main app.
            """)
            st.button(f"{label} ↗", on_click=permission.request_reference, args=[name], key=name)
        else:
            st.session_state.privileges_granted = True
            st.experimental_rerun()
        if not ref.bound_alias: return
    if st.button("Continue to app", type="primary"):
        st.session_state.privileges_granted = True
        st.experimental_rerun()
def get_references():
   app_name = session.get_current_database()
   data_frame = session.create_dataframe([''])
   refs = data_frame.select(call_udf('system$get_reference_definitions', lit(app_name))).collect()[0][0]
   references = []
   for row in json.loads(refs):
      bound_alias = row["bindings"][0]["alias"] if row["bindings"] else None
      references.append(Reference(row["name"], row["label"], row["object_type"], row["description"], bound_alias))
   return references
def get_ui_params():
    ray_cluster_config = json.loads(session.sql(f"call {current_database}.ray_app_public_schema.get_ray_cluster_config()").collect()[0]['GET_RAY_CLUSTER_CONFIG'])
    if 'ray_head' in ray_cluster_config:
        ray_head_instance_family = ray_cluster_config['ray_head']
        ray_head_instance_type_selector_index = instance_type_dict[ray_head_instance_family]
        query_warehouse = ray_cluster_config['query_warehouse']
        query_warehouse_selector_index = warehouse_type_dict[query_warehouse]
    else:
        ray_head_instance_type_selector_index = 7
        query_warehouse_selector_index = 3
    if 'ray_worker' in ray_cluster_config:
        ray_worker_specs = ray_cluster_config['ray_worker']
        ray_worker_instance_family = ray_worker_specs[0]
        ray_worker_instance_type_selector_index = instance_type_dict[ray_worker_instance_family]
        slider_num_ray_workers = ray_worker_specs[1]
    else:
        ray_worker_instance_type_selector_index = 7
        slider_num_ray_workers = 3
    if 'ray_custom_worker' in ray_cluster_config:
        ray_custom_worker_specs = ray_cluster_config['ray_custom_worker']
        ray_custom_worker_instance_family = ray_custom_worker_specs[0]
        ray_custom_worker_instance_type_selector_index = instance_type_dict[ray_custom_worker_instance_family]
        slider_num_ray_custom_workers = ray_custom_worker_specs[1]
    else:
        ray_custom_worker_instance_type_selector_index = 8
        slider_num_ray_custom_workers = 0
    return [ray_head_instance_type_selector_index, ray_worker_instance_type_selector_index, ray_custom_worker_instance_type_selector_index, slider_num_ray_workers, slider_num_ray_custom_workers, query_warehouse_selector_index]
def run_streamlit():
    with st.spinner(f"Initializing..."):
        has_app_been_initialized = session.sql(f"call {current_database}.ray_app_public_schema.has_app_been_initialized()").collect()[0]['HAS_APP_BEEN_INITIALIZED']
        [ray_head_instance_type_selector_index, ray_worker_instance_type_selector_index, ray_custom_worker_instance_type_selector_index, slider_num_ray_workers, slider_num_ray_custom_workers, query_warehouse_selector_index] = get_ui_params()
        with st.form("configuration"):
            st.write("Ray Cluster Configuration")
            col1, col2, col3, col4 = st.columns(4)
            with col1:
                cur_ray_head_instance_type = st.selectbox("Head:",instance_types, ray_head_instance_type_selector_index)
            with col2:
                cur_ray_worker_instance_type = st.selectbox("Worker:",instance_types, ray_worker_instance_type_selector_index)
                cur_num_ray_workers = st.slider("Select #:",0,10,slider_num_ray_workers, key='slider_worker')
            with col3: 
                cur_ray_custom_worker_instance_type = st.selectbox("Custom Worker:",instance_types, ray_custom_worker_instance_type_selector_index)
                cur_num_ray_custom_workers = st.slider("Select #:",0,10,slider_num_ray_custom_workers, key='slider_custom_worker')
            with col4: 
                cur_query_warehouse_type = st.selectbox("Warehouse:", warehouse_types, query_warehouse_selector_index )
            # Every form must have a submit button.
            left_button_col, cent_button_col1,cent_button_col2, right_button_col = st.columns(4)
            with cent_button_col1:
                submitted = st.form_submit_button("Create Cluster / Check Status")
            with cent_button_col2:
                deleted = st.form_submit_button("Delete Cluster")
            if submitted:
                with st.spinner(f"Submitting cluster configuration..."):
                    _ = session.sql(f"CALL {current_database}.ray_app_public_schema.recreate_ray_compute_pool_and_service('head', '{cur_ray_head_instance_type}', '{cur_ray_worker_instance_type}', '{cur_ray_custom_worker_instance_type}', '{cur_query_warehouse_type}', 1)").collect()
                    _ = session.sql(f"CALL {current_database}.ray_app_public_schema.recreate_ray_compute_pool_and_service('worker', '{cur_ray_head_instance_type}', '{cur_ray_worker_instance_type}', '{cur_ray_custom_worker_instance_type}', '{cur_query_warehouse_type}', {cur_num_ray_workers})").collect()
                    _ = session.sql(f"CALL {current_database}.ray_app_public_schema.recreate_ray_compute_pool_and_service('custom_worker', '{cur_ray_head_instance_type}', '{cur_ray_worker_instance_type}', '{cur_ray_custom_worker_instance_type}', '{cur_query_warehouse_type}', {cur_num_ray_custom_workers})").collect()
            if deleted:
                with st.spinner(f"Deleting cluster..."):
                    _ = session.sql("CALL delete_ray_cluster()").collect()
            if submitted or deleted:
                [ray_head_instance_type_selector_index, ray_worker_instance_type_selector_index, ray_custom_worker_instance_type_selector_index, slider_num_ray_workers, slider_num_ray_custom_workers, query_warehouse_selector_index] = get_ui_params()
                has_app_been_initialized = session.sql(f"call {current_database}.ray_app_public_schema.has_app_been_initialized()").collect()[0]['HAS_APP_BEEN_INITIALIZED']
            st.write('\n\n')
            st.write('\n\n')
            st.write('\n\n')
            st.write('\n\n')
            st.write('\n\n')
            if has_app_been_initialized:
                col6, col7, col8 = st.columns(3)
                with col6:
                    st.caption("Ray Head Service Status:")
                    ray_head_service_status = session.sql(f"CALL {current_database}.ray_app_public_schema.get_ray_service_status('head')").collect()[0]['GET_RAY_SERVICE_STATUS']
                    st.write(ray_head_service_status)
                with col7:
                    st.caption("Ray Worker Service Status:")
                    ray_worker_service_status = session.sql(f"CALL {current_database}.ray_app_public_schema.get_ray_service_status('worker')").collect()[0]['GET_RAY_SERVICE_STATUS']
                    st.write(ray_worker_service_status)
                with col8:
                    st.caption("Ray Custom Worker Service Status:")
                    ray_worker_service_status = session.sql(f"CALL {current_database}.ray_app_public_schema.get_ray_service_status('custom_worker')").collect()[0]['GET_RAY_SERVICE_STATUS']
                    st.write(ray_worker_service_status)
                st.caption("Endpoints:")
                urls = session.sql(f"CALL {current_database}.ray_app_public_schema.get_ray_public_endpoints()").collect()[0]['GET_RAY_PUBLIC_ENDPOINTS']
                st.write(urls)
                
if __name__ == '__main__':
   if 'privileges_granted' not in st.session_state:
      setup()
   else:
      run_streamlit()