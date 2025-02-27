import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List

import docker
import yaml


class subprocessRunner:
    def run(self, cmd):
        proc = self._start_proc(cmd)
        for line in self._get_stdout(proc):
            l = line.decode()
            print(l.replace("\n", ""))
        return proc.returncode

    def _start_proc(self, cmd):
        return subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            shell=True,
        )

    def _get_stdout(self, proc):
        while True:
            line = proc.stdout.readline()
            if line:
                yield line
            if proc.poll() is not None:
                break


class zmkContainer:
    def __init__(self, name, mountdir, force_new=False):
        # self.IMAGE = "zmkfirmware/zmk-dev-arm:stable"
        self.IMAGE = "zmkfirmware/zmk-dev-arm:3.5"
        self.docker_cli = docker.from_env()
        if force_new:
            self._remove_container(name)
        self._pull_image(self.IMAGE)
        self.container = self._start_container(name, mountdir)
        self.mountdir = mountdir
        self.name = name

    def _pull_image(self, IMAGE):
        try:
            self.docker_cli.images.get(IMAGE)
        except docker.errors.ImageNotFound:
            subprocessRunner().run("docker pull %s" % IMAGE)

    def _start_container(self, name, workdir):
        try:
            container = self.docker_cli.containers.get(name)
            print("container already running")
        except docker.errors.NotFound:
            print("running new container")
            container = self.docker_cli.containers.run(
                self.IMAGE,
                name=name,
                volumes=[f"{workdir}:{workdir}"],
                working_dir=str(workdir),
                command="tail -F /dev/null",
                detach=True,
            )

        if container.status == "exited":
            container.start()
        while True:
            container = self.docker_cli.containers.get(name)
            if container.status == "running":
                break
            time.sleep(1)
        self.container = container
        return container

    def _remove_container(self, name):
        try:
            container = self.docker_cli.containers.get(name)
        except docker.errors.NotFound:
            return

        print("killing existing container")
        if container.status == "running":
            container.stop()
        container.remove()

    def exec(self, cmd, workdir: Path):
        print("executing : %s" % cmd)
        _, responce = self.container.exec_run(cmd, workdir=str(workdir), stream=True)
        for line in responce:
            print(line.decode(), end="")


class zmkBuilder:
    def __init__(self, yaml_file: Path):
        self.container_name = yaml_file.parent.name

        self.yaml_file = yaml_file
        self.curdir = yaml_file.parent.resolve()
        self.boardsdir = self.curdir / "boards"
        self.confdir = self.curdir / "config"

        self.workdir_top = self.curdir / "zmk_work"
        self.workdir = self.workdir_top / "zmk"
        self.wconfdir = self.workdir / "config"
        self.wboardsdir = self.wconfdir / "boards"
        self.wbuilddir = self.workdir / "build"

        if not self.boardsdir.exists():
            raise Exception("boards directory not fourd : %s" % self.boardsdir)
        if not self.confdir.exists():
            raise Exception("conf directory not fourd : %s" % self.confdir)

        self._add_gitignore()
        self.workdir_top.mkdir(exist_ok=True)

    def _add_gitignore(self):
        gitignore = self.curdir / ".gitignore"
        if gitignore.exists():
            with open(gitignore, "r") as f:
                lines = f.readlines()
            for line in lines:
                if line.startswith(self.workdir_top.name):
                    return

        with open(gitignore, "a") as f:
            f.write(self.workdir_top.name)

    def init(self):
        self.container = zmkContainer(self.container_name, self.workdir_top, force_new=True)
        if self.workdir.exists():
            self.container.exec(f"chmod 777 -R .", self.workdir)
            shutil.rmtree(self.workdir)
        self.workdir.mkdir(exist_ok=True, parents=True)
        shutil.copytree(self.confdir, self.wconfdir, dirs_exist_ok=True)
        self.container.exec(f"west init -l {self.wconfdir}", self.workdir)

    def update(self):
        self.container = zmkContainer(self.container_name, self.workdir_top)
        shutil.copytree(self.confdir, self.wconfdir, dirs_exist_ok=True)
        self.container.exec(f"west update", self.workdir)

    def build(self, prinstine):
        self.container = zmkContainer(self.container_name, self.workdir_top)
        self.wbuilddir.mkdir(exist_ok=True)
        self.container.exec(f"west zephyr-export", self.workdir)
        shutil.copytree(self.boardsdir, self.wboardsdir, dirs_exist_ok=True)
        build_list = self._parse_build_list(self.yaml_file)
        print("build list : %s" % build_list)
        for board, shield, snippet, cmake_args in build_list:
            print("building %s-%s" % (board, shield))
            if snippet != "":
                print(" - snippet = %s" % snippet)
            if cmake_args != "":
                print(" - cmake_args = %s" % cmake_args)
            builddir = self.wbuilddir / shield
            self._build(board, shield, builddir, prinstine, snippet=snippet, cmake_args=cmake_args)
            self.container.exec(f"chmod 777 -R .", builddir)
            uf2 = self.wbuilddir / shield / "zephyr/zmk.uf2"
            if uf2.exists():
                shutil.copy(uf2, self.workdir_top / (shield + ".uf2"))
            else:
                print("uf2 not found")
                raise Exception("build failed, uf2 not found")

    def _parse_build_list(self, yaml_file):
        with open(yaml_file, "r") as yml:
            config = yaml.safe_load(yml)
        if config is None:
            raise Exception("build.yaml is empty")
        if "include" not in config:
            raise Exception("'include' node is required in build.yaml")

        ret = []
        for c in config["include"]:
            if "board" not in c or "shield" not in c:
                raise Exception("both 'board' and 'shield' node is required in build.yaml::include")
            board = c["board"]
            shield = c["shield"]
            snippet = c["snippet"] if "snippet" in c else ""
            cmake_args = c["cmake-args"] if "cmake-args" in c else ""
            ret.append([board, shield, snippet, cmake_args])
            # if isinstance(c["shield"], str):
            #     ret.append([c["board"], c["shield"]])
            # elif isinstance(c["shield"], list):
            #     for shield in c["shield"]:
            #         ret.append([c["board"], shield])

        return ret

    def _build(self, board, shield, builddir, prinstine, snippet="", cmake_args=""):
        appdir = self.workdir / "zmk/app"
        prinstine_flag = "-p" if prinstine else ""
        snippet_flag = "" if snippet == "" else f"-S {snippet}"
        # fmt: off
        cmd = " ".join(
            [
                "west", "build",
                prinstine_flag,
                "-s", str(appdir),
                "-b", board,
                "-d", str(builddir),
                snippet_flag,
                "--",
                f"-DSHIELD={shield}",
                f"-DZMK_CONFIG={str(self.wconfdir)}",
                cmake_args
            ]
        )
        # fmt: on
        # cmd = f"west build {prinstine_flag} -s {appdir} -b {board} -d {builddir} -- -DSHIELD={shield} -DZMK_CONFIG={self.wconfdir}"
        print("==build==")
        print(f" workdir = {self.workdir}")
        print(f" cmd = {cmd}")
        self.container.exec(cmd, self.workdir)


def main(yaml_list: List[Path], init: bool, update: bool, prinstine: bool):
    for yaml_file in yaml_list:
        zmk_builder = zmkBuilder(yaml_file)
        if init:
            zmk_builder.init()
        if update or init:
            zmk_builder.update()
        zmk_builder.build(prinstine)


def handle_args(args: List[str]):
    parser = argparse.ArgumentParser()
    parser.add_argument("build_yaml", nargs="+", type=Path)
    parser.add_argument("--init", action="store_true", default=False)
    parser.add_argument("--update", action="store_true", default=False)
    parser.add_argument("--prinstine", "-p", action="store_true", default=False)
    parsed = parser.parse_args(args)

    build_yaml: Path = parsed.build_yaml
    for yaml_file in build_yaml:
        if not yaml_file.exists():
            raise Exception("file not found : %s" % yaml_file)

    ret = {
        "yaml_list": build_yaml,
        "init": parsed.init,
        "update": parsed.update,
        "prinstine": parsed.prinstine,
    }
    return ret


if __name__ == "__main__":
    if "debugpy" in sys.modules:
        args = ["keyboards/zmk-config-fish/build.yaml", "-p"]
        # args = ["keyboards/zmk-config-d3kb2/build.yaml"]
        # args = ["keyboards/zmk-config-d3kb/build.yaml", "--init"]
    else:
        args = sys.argv[1:]

    main(**handle_args(args))
