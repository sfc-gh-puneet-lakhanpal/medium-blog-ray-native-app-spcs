Now go to ray-native-app-spcs/service folder and push images to docker

cd /Users/plakhanpal/Documents/git/ray-native-app-spcs/ray-native-app-spcs/service/grafana
docker build --rm --platform linux/amd64 -t native_app_grafana .
cd ..
cd prometheus
docker build --rm --platform linux/amd64 -t native_app_prometheus .
cd ..
cd ray_base
docker build --rm --platform linux/amd64 -t native_app_ray_base .
cd ..
cd ray_head
docker build --rm --platform linux/amd64 -t native_app_ray_head .
cd ..
cd ray_worker
docker build --rm --platform linux/amd64 -t native_app_ray_worker .
cd ..
cd ray_custom_worker
docker build --rm --platform linux/amd64 -t native_app_ray_custom_worker .
cd ..
REPO_URL=$(snow spcs image-repository url ray_provider_db.ray_provider_schema.ray_provider_image_repo --role ray_provider_role)
echo $REPO_URL

docker tag native_app_grafana $REPO_URL/native_app_grafana
docker tag native_app_prometheus $REPO_URL/native_app_prometheus
docker tag native_app_ray_head $REPO_URL/native_app_ray_head
docker tag native_app_ray_worker $REPO_URL/native_app_ray_worker
docker tag native_app_ray_custom_worker $REPO_URL/native_app_ray_custom_worker

snow spcs image-registry login

docker push $REPO_URL/native_app_grafana
docker push $REPO_URL/native_app_prometheus
docker push $REPO_URL/native_app_ray_head
docker push $REPO_URL/native_app_ray_worker
docker push $REPO_URL/native_app_ray_custom_worker


snow spcs image-repository list-images ray_provider_db.ray_provider_schema.ray_provider_image_repo --role ray_provider_role

cd ..