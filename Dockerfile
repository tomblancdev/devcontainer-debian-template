FROM debian:latest as builder

ARG USER=user
ARG USER_GROUP=user
ARG USER_PASSWORD
ARG USER_SUDO=false
ARG UID=1000
ARG GID=1000

# Set environment variables
ENV ZSH_THEME=agnoster
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Check if user is root
RUN if [ $(id -u) -eq 0 || ${USER} = "root" ]; then echo "Please do not run this container as root"; exit 1; fi

RUN apt update && apt upgrade && apt install -y \
    git \
    zsh \
    sudo \
    curl \
    locales \
    locales-all \
    build-essential
# Create user
RUN groupadd -g ${GID} ${USER_GROUP} && \
    useradd -m -u ${UID} -g ${GID} -s ${USER_SHELL} ${USER} && \
    usermod -aG sudo ${USER} && \
    echo "${USER}:${USER_PASSWORD}" | chpasswd

# Enable sudo
RUN if [ ${USER_SUDO} = "true" ]; then usermod -aG sudo ${USER}; fi

# Install Oh My Zsh for root and user
RUN sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && sed -i "s/robbyrussell/"'$ZSH_THEME'"/g" /root/.zshrc;

USER ${USER}
# set the default shell for the user to zsh if the user is not root
RUN if [ $USER != "root" ]; \
    then \
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
    sed -i "s/robbyrussell/"'$ZSH_THEME'"/g" /home/$USER/.zshrc; \
    fi

USER root
# Set zsh as default shell for root
RUN chsh -s $(which zsh) 
# Set zsh as default shell for user
RUN chsh -s $(which zsh) ${USER}

FROM builder as pipx
USER root
# Install pipx
RUN apt install -y pipx

FROM pipx as pre-commit
# To use it in another stage :
# RUN apt install -y python3
# COPY --from=pre-commit /usr/local/bin/pre-commit /usr/local/bin/pre-commit
# COPY --from=pre-commit /usr/share/pipx/venvs/pre-commit /usr/share/pipx/venvs/pre-commit
USER root
# Install pre-commit
RUN pipx install pre-commit
# create directory for pre-commit venv
RUN mkdir -p /usr/share/pipx/venvs
# Move pre-commit venv to /usr/share/venvs/pre-commit
RUN mv /root/.local/pipx/venvs/pre-commit /usr/share/pipx/venvs
# Set permissions to execute pre-commit
RUN chmod a+x -R /usr/share/pipx/venvs/pre-commit
# replace "#!/root/.local/pipx/venvs/pre-commit/bin/python" in /usr/share/pipx/venvs/pre-commit/bin/pre-commit
RUN sed -i 's|#!/root/.local/pipx/venvs/pre-commit/bin/python|#!/usr/share/pipx/venvs/pre-commit/bin/python|g' /usr/share/pipx/venvs/pre-commit/bin/pre-commit
# Move pre-commit to /usr/local/bin
RUN mv /usr/share/pipx/venvs/pre-commit/bin/pre-commit /usr/local/bin

FROM pipx as poetry
# To use it in another stage :
# COPY --from=poetry /usr/local/bin/poetry /usr/local/bin/poetry
# COPY --from=poetry /usr/share/pipx/venvs/poetry /usr/share/pipx/venvs/poetry
#  # To use it with pyenv (You may have installed pyenv before) :
# RUN poetry config virtualenvs.prefer-active-python true
# RUN su $USER -c "poetry config virtualenvs.prefer-active-python true"
ARG POETRY_VERSION
USER root
# Install poetry
RUN if [ -z ${POETRY_VERSION} ]; \
    then pipx install poetry; \
    else pipx install poetry==${POETRY_VERSION};\
    fi
# Create directory for poetry venv
RUN mkdir -p /usr/share/pipx/venvs
# Move poetry venv to /usr/share/pipx/venvs/poetry
RUN mv /root/.local/pipx/venvs/poetry /usr/share/pipx/venvs
# Set permissions to execute poetry
RUN chmod a+x -R /usr/share/pipx/venvs/poetry
# Replace "#!/root/.local/pipx/venvs/pre-commit/bin/python" with "#!/usr/share/pipx/venvs/poetry/bin/python3" in /usr/share/pipx/venvs/poetry/bin/poetry
RUN sed -i 's|#!/root/.local/pipx/venvs/poetry/bin/python|#!/usr/share/pipx/venvs/poetry/bin/python|g' /usr/share/pipx/venvs/poetry/bin/poetry
# Move poetry to /usr/local/bin
RUN mv /usr/share/pipx/venvs/poetry/bin/poetry /usr/local/bin


FROM builder as bun
USER root
# Install requiered packages 
RUN apt install unzip
# Install Bun for root
RUN curl -fsSL https://bun.sh/install | bash
# Move bun to /usr/local/bin
RUN mv /root/.bun/bin/bun /usr/local/bin
# Set permissions to execute bun
RUN chmod a+x /usr/local/bin/bun

FROM builder as pyenv
# To use it in another stage :
RUN apt install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    curl \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev
# COPY --from=pyenv /usr/share/pyenv /usr/share/pyenv
# RUN ln -s /usr/share/pyenv/bin/pyenv /usr/local/bin/pyenv
# RUN echo "eval \"\$(pyenv init --path)\"" >> /home/$USER/.zshrc
# RUN echo "eval \"\$(pyenv init --path)\"" >> /root/.zshrc
# # To install python with pyenv
# ARG PYTHON_VERSION=3.12
# RUN pyenv install ${PYTHON_VERSION}
# RUN pyenv global ${PYTHON_VERSION}
USER root
# Install requiered packages
RUN curl https://pyenv.run | bash
# create directory for pyenv
RUN mkdir -p /usr/share/pyenv
# Move pyenv to /usr/share/pyenv
RUN cp -r /root/.pyenv/* /usr/share/pyenv
# Create symlink to /usr/local/bin/pyenv
RUN ln -s /usr/share/pyenv/bin/pyenv /usr/local/bin/pyenv
RUN echo "eval \"\$(pyenv init --path --no-rehash)\"" >> /root/.zshrc
RUN su $USER -c "echo \"eval \"\$(pyenv init --path --no-rehash)\"\" >> /home/$USER/.zshrc"

FROM builder as development
USER root

# Set Arguments
ARG WORKSPACE=/workspace

# Copy pre-commit venv from pre-commit stage
RUN apt install -y python3
COPY --from=pre-commit /usr/share/pipx/venvs/pre-commit /usr/share/pipx/venvs/pre-commit
COPY --from=pre-commit /usr/local/bin/pre-commit /usr/local/bin/pre-commit

# Copy bun from bun stage
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

# Copy pyenv from pyenv stage
RUN apt install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    curl \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev
COPY --from=pyenv /usr/share/pyenv /usr/share/pyenv
RUN ln -s /usr/share/pyenv/bin/pyenv /usr/local/bin/pyenv
RUN echo "eval \"\$(pyenv init --path --no-rehash)\"" >> /home/$USER/.zshrc
RUN echo "eval \"\$(pyenv init --path --no-rehash)\"" >> /root/.zshrc
# To install python with pyenv
ARG PYTHON_VERSION=3.12
ENV PYENV_ROOT=/usr/share/pyenv
# allow all users to use pyenv
RUN pyenv install ${PYTHON_VERSION}
RUN pyenv global ${PYTHON_VERSION}

# Copy poetry from poetry stage
ENV POETRY_VIRTUALENVS_IN_PROJECT=true
COPY --from=poetry /usr/share/pipx/venvs/poetry /usr/share/pipx/venvs/poetry
COPY --from=poetry /usr/local/bin/poetry /usr/local/bin/poetry
# To use it with pyenv (You may have installed pyenv before) :
RUN poetry config virtualenvs.prefer-active-python true
RUN su $USER -c "poetry config virtualenvs.prefer-active-python true"

# Create workspace folder and set permissions
RUN mkdir -p ${WORKSPACE} && \
    chown -R ${USER}:${USER_GROUP} ${WORKSPACE} && \
    chmod -R 775 ${WORKSPACE}

USER ${USER}
WORKDIR ${WORKSPACE}

# Run a long-lived process
CMD tail -f /dev/null