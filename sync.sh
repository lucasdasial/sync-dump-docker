#!/bin/bash
echo -e "::: Bem vindo à sincronização do banco de dados do projeto ::: \n"
sleep 1

check_utility() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "Ops! Parece que você esqueceu do $1! 👽 Instale-o e vamos tentar novamente, ok?\n"
        exit 1;
    }
}

verify_dependencies() {
    sleep 1
    echo -e "Verificando as dependencias \n"
    sleep 1
    check_utility heroku
    check_utility mix

    if [ "$DBLOCATION" == "1" ]; then
        check_utility pg_restore
    fi

    echo -e "Qual é o nome de usuário para 'pg_restore'? (default: postgres)"
    read -r USERNAME

    if [ -z "$USERNAME" ]; then
        USERNAME='postgres'
    fi
    echo -e "USER -> $USERNAME \n"
    sleep 1

    if [ "$DBLOCATION" == "2" ]; then
        check_utility docker
        echo -e "Qual o nome do container que esta rodando o postgres?\n(default: b2-db-1)"
        read -r CONTAINERNAME

        if [ -z "$CONTAINERNAME" ]; then
            CONTAINERNAME='b2-db-1'
        fi
        echo -e "CONTAINER -> $CONTAINERNAME \n"   
    fi

    sleep 1
    echo -e "Tudo certo, todas as dependencias estão Ok ❇️"
    sleep 1
    echo -e "Proseguindo ... \n"
    sleep 1

}

select_db_location() {
    echo -e "Aonde será executando a sincronização?"
    sleep 1
    echo -e "[1] - Sistema operacional ⚙️"
    echo -e "[2] - Container Docker 🐳"
    read -r DBLOCATION

    if [ "$DBLOCATION" != "1" ] && [ "$DBLOCATION" != "2" ]; then
        echo -e "\nOpção inválida 💢"
        sleep 1
        select_db_location
        return
    fi

    echo -e "Local de execução selecionado 🆗\n"
}

confirm_action() {
    sleep 1
    read -p "DESEJA CONTINUAR? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "Ok, sincronização cancelada 🚫\n"
        exit 1
    fi
}

check_postgres_up(){
    echo -e "\nParece que seu postgres não esta rodando 🐘❌\n"

    if [ "$DBLOCATION" == "2" ]; then
        sleep 1
        echo -e "Montando um container a partir do compose file do prejeto \n"
        docker compose up -d
    else
        echo -e "Certifique-se que tenha uma instancia do postgres disponível\n"
        exit 1
    fi
   
  

}

reset_db(){
    echo -e "☢️ O banco atual será apagado e recriado. ☢️\n"
    confirm_action

    make_backup

    mix ecto.drop || check_postgres_up
    sleep 1
    mix ecto.create

    sleep 1
    echo -e "\nBanco recriado ❇️ \n"
    sleep 1
}


select_env_to_sync() {
    echo -e "Em qual ambiente deseja sincronizar? 'staging' ou 'production'?\n"
    echo -e "[1] - Staging 🌱"
    echo -e "[2] - Produção 🚧"
    read -r OPTION

    if [ "$OPTION" != "1" ] && [ "$OPTION" != "2" ]; then
        echo -e "\nOpção inválida 💢"
        sleep 1
        select_env_to_sync
        return
    fi

    if [ "$OPTION" == "1" ]; then
        AMBIENTE="staging"
    else
        AMBIENTE="production"
    fi

    echo -e "Ambiente selecionado 🆗\n"
}

delete_old_dump_if_exist(){
    if [ -f latest.dump ]; then
        echo -e "Apagando dump antigo 👋\n"
        rm latest.dump
    fi
}

get_new_dump(){
    sleep 1
    echo -e "Baixando um dump atualizado 🆕 \n"
    heroku pg:backups:download -a bembank-"$AMBIENTE"
}


make_backup(){
    last_backup_date=$(heroku pg:backups -a bembank-"$AMBIENTE" | grep -E '^[bB][0-9]+' | awk 'NR==1{print $2 " " $3}')
    last_backup_timestamp=$(date --date="$last_backup_date" +%s)
    current_timestamp=$(date +%s)
    time_difference=$((current_timestamp - last_backup_timestamp))
    one_day_seconds=$((24 * 3600))

    echo -e "Verificando se há algum backup recente\n"

    if (( time_difference > one_day_seconds )); then
        sleep 1
        echo -e "Último backup feito a mais de um dia.\n"
        sleep 1
        echo -e "Fazendo um novo backup! 🚀\n"
        heroku pg:backups:capture -a bembank-"$AMBIENTE"
    else
        sleep 1
        echo -e "Relaxa! você um ja possui um backup feito nas últimas 24h😌\n"
    fi
}

execute_sync_docker(){
    echo -e "Copiando o dump novo para seu container docker! 🐳\n"
    docker cp latest.dump "$CONTAINERNAME":/home/circleci/project
    sleep 1
    echo -e "Dump copiado para container ❇️ \n"

    docker exec -i "$CONTAINERNAME" pg_restore --verbose --clean --no-acl --no-owner -h localhost -U "$USERNAME" -d b2_dev latest.dump
}

execute_sync_local(){
    pg_restore --verbose --clean --no-acl --no-owner -h localhost -U "$USERNAME" -d b2_dev latest.dump
}


select_db_location
verify_dependencies
select_env_to_sync
reset_db
delete_old_dump_if_exist
get_new_dump


if [ "$DBLOCATION" == "1" ]; then
    execute_sync_local
fi

if [ "$DBLOCATION" == "2" ]; then
    execute_sync_docker
fi

echo -e "✅ Sincronização concluída! ✅\n"
exit 1
