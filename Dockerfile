ARG ROS_DISTRO=humble
ARG PREFIX=

FROM husarnet/ros:${PREFIX}${ROS_DISTRO}-ros-base AS package-builder

ARG PREFIX

# https://github.com/cyberbotics/webots/tags
ARG WEBOTS_VERSION=R2023b
ARG WEBOTS_PACKAGE_PREFIX=

RUN apt-get update && apt-get install --yes wget bzip2 && rm -rf /var/lib/apt/lists/ && \
    wget https://github.com/cyberbotics/webots/releases/download/$WEBOTS_VERSION/webots-$WEBOTS_VERSION-x86-64$WEBOTS_PACKAGE_PREFIX.tar.bz2 && \
    tar xjf webots-*.tar.bz2 && rm webots-*.tar.bz2

RUN apt-get update -y && apt-get install -y git python3-colcon-common-extensions python3-vcstool python3-rosdep curl

WORKDIR /ros2_ws

RUN cd  /ros2_ws && \
    git clone https://github.com/husarion/webots_ros2.git src/webots_ros2 -b 2024a && \
    cd src/webots_ros2 && \
    git submodule update --init

SHELL ["/bin/bash", "-c"]

RUN MYDISTRO=${PREFIX:-ros}; MYDISTRO=${MYDISTRO//-/} && \
    source /opt/$MYDISTRO/$ROS_DISTRO/setup.bash && \
    # without this line (using vulcanexus base image) rosdep init throws error: "ERROR: default sources list file already exists:"
    rm -rf /etc/ros/rosdep/sources.list.d/20-default.list && \
    rosdep init && \
    rosdep update --rosdistro $ROS_DISTRO && \
    rosdep install --ignore-src --from-path src/webots_ros2/ -y --rosdistro $ROS_DISTRO
RUN source /opt/ros/${ROS_DISTRO}/setup.bash && colcon build

FROM husarnet/ros:${PREFIX}${ROS_DISTRO}-ros-base

SHELL ["/bin/bash", "-c"]
ARG ROS_DISTRO
ENV ROS_DISTRO $ROS_DISTRO

COPY --from=package-builder /webots/ /usr/local/webots/

ENV QTWEBENGINE_DISABLE_SANDBOX=1
ENV WEBOTS_HOME /usr/local/webots
ENV PATH /usr/local/webots:${PATH}

# Disable dpkg/gdebi interactive dialogs
ENV DEBIAN_FRONTEND=noninteractive

# Install Webots runtime dependencies
RUN apt-get update && apt-get install -y \
    wget && \
    rm -rf /var/lib/apt/lists/ && \
    wget https://raw.githubusercontent.com/cyberbotics/webots/master/scripts/install/linux_runtime_dependencies.sh && \
    chmod +x linux_runtime_dependencies.sh && ./linux_runtime_dependencies.sh && rm ./linux_runtime_dependencies.sh && rm -rf /var/lib/apt/lists/

COPY --from=package-builder /ros2_ws /ros2_ws

WORKDIR /ros2_ws

RUN ls -R /ros2_ws && apt-get update --fix-missing -y && apt-get install -y python3-rosdep && \
    # without this line (using vulcanexus base image) rosdep init throws error: "ERROR: default sources list file already exists:"
    rm -rf /etc/ros/rosdep/sources.list.d/20-default.list && \
    rosdep init && \
    rosdep update --rosdistro $ROS_DISTRO && \
    rosdep install --ignore-src --from-path src/webots_ros2/ -r -y --rosdistro $ROS_DISTRO  && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV USERNAME=root

RUN echo $(cat /ros2_ws/src/webots_ros2/webots_ros2_husarion/package.xml | grep '<version>' | sed -r 's/.*<version>([0-9]+.[0-9]+.[0-9]+)<\/version>/\1/g') >> /version.txt
