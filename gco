#!/bin/bash

# 检查参数数量
if [ $# -lt 2 ]; then
    echo "用法: gco [源文件1] [源文件2] ... [目标文件] [可选选项]"
    exit 1
fi

# 获取所有参数
all_args=("$@")

# 分离源文件和目标文件及选项
source_files=()
target_file=""
options=()

# 遍历所有参数
for arg in "${all_args[@]}"; do
    if [[ "$arg" == *.c ]]; then
        source_files+=("$arg") # 如果是 .c 文件，加入源文件列表
    else
        if [ -z "$target_file" ]; then
            target_file="$arg" # 第一个非 .c 文件视为目标文件
        else
            options+=("$arg") # 其余非 .c 文件视为选项
        fi
    fi
done

# 检查源文件数量
if [ ${#source_files[@]} -eq 0 ]; then
    echo "错误: 未提供源文件"
    exit 1
fi

# 检查 exe 文件夹是否存在，如果不存在则创建
if [ ! -d "./exe" ]; then
    mkdir -p "./exe"
    echo "创建 ./exe 文件夹"
fi

# SQLite 数据库文件
db_file="$HOME/.bin/compile_records.db"

# 初始化数据库（如果不存在）
if [ ! -f "$db_file" ]; then
    sqlite3 "$db_file" "CREATE TABLE records (source_file TEXT PRIMARY KEY, executable TEXT);"
fi

# 如果源文件已经编译过，删除旧的可执行文件
for source_file in "${source_files[@]}"; do
    absolute_source_file=$(realpath "$source_file")  # 获取源文件的绝对路径
    old_executable=$(sqlite3 "$db_file" "SELECT executable FROM records WHERE source_file='$absolute_source_file';")
    if [ -n "$old_executable" ]; then
        if [ -f "$old_executable" ]; then
            rm "$old_executable"
            echo "删除旧的可执行文件: $old_executable"
        fi
        # 删除旧记录
        sqlite3 "$db_file" "DELETE FROM records WHERE source_file='$source_file';"
    fi
done

# 查找 MariaDB 头文件和库路径
find_mariadb_paths() {
    local base_paths=(
        "/usr"
        "/usr/local"
        "/usr/lib/x86_64-linux-gnu"
    )
    
    for base in "${base_paths[@]}"; do
        if [ -d "$base/include/mariadb" ] && [ -d "$base/lib" ]; then
            echo "$base"
            return
        fi
    done
}

# 处理 -m 选项
if [[ " ${options[@]} " == *" -m "* ]]; then
    mariadb_base=$(find_mariadb_paths)
    mariadb_include_path="$mariadb_base/include/mariadb"
    mariadb_lib_path="$mariadb_base/lib"
    echo "找到 MariaDB 头文件路径: $mariadb_include_path"
    echo "找到 MariaDB 库路径: $mariadb_lib_path"

    # 添加 -I 和 -L 及 -lmariadb 选项
    mariadb_options="-I$mariadb_include_path -L$mariadb_lib_path -lmariadb"

    # 从 options 中移除 -m
    options=("${options[@]/-m/}")
else
    mariadb_options=""
fi

# 执行编译命令
gcc -o "./exe/$target_file" "${source_files[@]}" $mariadb_options "${options[@]}"

# 检查编译是否成功
if [ $? -eq 0 ]; then
    echo "编译成功: ./exe/$target_file"
    # 记录源文件和可执行文件的对应关系
    for source_file in "${source_files[@]}"; do
        source_file_path=$(realpath "$source_file") 
        dir_path=$(dirname "$source_file_path")
        sqlite3 "$db_file" "INSERT INTO records (source_file, executable) VALUES ('$source_file_path', '$dir_path/exe/$target_file');"
        break
    done
else
    echo "编译失败"
fi
