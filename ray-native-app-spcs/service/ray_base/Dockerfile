FROM nvidia/cuda:12.1.0-cudnn8-devel-ubuntu22.04
RUN apt-get update -y
RUN apt-get install -y python3-pip git net-tools wget
RUN pip3 install --upgrade pip
# Install CUDA-enabled PyTorch (CUDA 12.1 wheels) before the rest to ensure GPU builds
RUN pip3 install --index-url https://download.pytorch.org/whl/cu121 torch torchvision torchaudio
COPY requirements.txt ./
RUN pip3 install -r requirements.txt
COPY entrypoint.sh ./