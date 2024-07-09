FROM nvidia/cuda:12.1.0-cudnn8-devel-ubuntu22.04
RUN apt-get update -y
RUN apt-get install -y python3-pip git net-tools wget
RUN pip3 install --upgrade pip
COPY ray_requirements.txt ./
RUN pip3 install -r ray_requirements.txt
COPY usecase_requirements.txt ./
RUN pip3 install -r usecase_requirements.txt
COPY entrypoint.sh ./