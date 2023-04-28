#!/bin/bash

# Define the menu options
os_options=("ubuntu" "opensuse-leap" )
os_version_options=("20.04" "22.04")
k8s_options=("k3s" "rke2" "kubeadm")
k8s_version=("--K8S_VERSION=1.24.6" "--K8S_VERSION=1.25.2")
default_repository="ttl.sh"
# Print the menu
while true; do
    while true; do
        echo "Choose an OS flavor:"
        # Loop over the options and print each one with a number
        for i in "${!os_options[@]}"; do
            echo "$i. ${os_options[$i]}"
        done

        # Prompt the user to choose an option
        read -p "Enter the number of your choice: " os_choice

        # Validate the choice and set the OS_FLAVOR variable

        if [[ "$os_choice" =~ ^[0-9]+$ ]] && (( os_choice >= 0 && os_choice < ${#os_options[@]} )); then
            OS_FLAVOR=${os_options[$os_choice]}
            echo "You chose OS_FLAVOR: $OS_FLAVOR"
            echo

            # Prompt the user to enter the OS_VERSION if Ubuntu is selected
            if [[ "$OS_FLAVOR" == "ubuntu" ]]; then
                while true; do
                    # Print the OS_VERSION menu
                    echo "Choose an OS version:"

                    # Loop over the OS_VERSION options and print each one with a number
                    for i in "${!os_version_options[@]}"; do
                        echo "$i. ${os_version_options[$i]}"
                    done

                    # Prompt the user to choose an OS_VERSION option
                    read -p "Enter the number of your choice: " os_version_choice

                    # Validate the OS_VERSION choice and set the OS_VERSION variable
                    if [[ "$os_version_choice" =~ ^[0-9]+$ ]] && (( os_version_choice >= 0 && os_version_choice < ${#os_version_options[@]} )); then
                        OS_VERSION=${os_version_options[$os_version_choice]}
                        echo "You chose OS_VERSION: $OS_VERSION"
                        echo
                        break
                    else
                        echo "Invalid choice"
                        continue
                    fi
                done
            fi
        break
        else
            echo "Invalid choice"
            continue
        fi
    done


    # Print the K8S_FLAVOR menu
    while true; do
        echo "Choose a K8S flavor:"
        # Loop over the K8S_FLAVOR options and print each one with a number
        for i in "${!k8s_options[@]}"; do
            echo "$i. ${k8s_options[$i]}"
        done

            # Prompt the user to choose a K8S_FLAVOR option
        read -p "Enter the number of your choice: " k8s_choice

            # Validate the K8S_FLAVOR choice and set the K8S_FLAVOR variable
        if [[ "$k8s_choice" =~ ^[0-9]+$ ]] && (( k8s_choice >= 0 && k8s_choice < ${#k8s_options[@]} )); then
            K8S_FLAVOR=${k8s_options[$k8s_choice]}
            echo "You chose K8S_FLAVOR: $K8S_FLAVOR"
            echo
            break
        else
            echo "Invalid choice"
            continue
        fi
    done
    while true; do
        read -e -p "Environment name (lowercase, '-', and 0-9): " CANVOS_ENV
        if [[ "$CANVOS_ENV" =~ ^[a-z0-9-]+$ ]]; then
            echo
            echo "You Entered: $CANVOS_ENV"
            echo
            break

        else
            echo "Input is invalid (lowercase, '-', and 0-9)."
            continue
        fi
    done
    while true; do
        read -e -i "$default_repository" -p "Image Repository Name (i.e ttl.sh): " IMAGE_REPOSITORY
        if [[ "$IMAGE_REPOSITORY" =~ ^[A-Za-z0-9_.-]+$ ]]; then
            echo
            echo "You Entered: $IMAGE_REPOSITORY"
            echo
            break
        else
            echo "Input is invalid."
            continue
        fi
    done
    while true; do
        read -e -p "ISO name: " ISO_NAME
        if [[ "$ISO_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
            echo
            echo "You Entered: $ISO_NAME"
            echo
            break
        else
            echo "Input is invalid (lowercase, uppercase. '_', '-', and 0-9)."
            continue
        fi
    done
    if [[ "$OS_FLAVOR" == "ubuntu" ]]; then
        # Print the OS_VERSION menu
        echo -e "OS_FLAVOR=$OS_FLAVOR\nOS_VERSION: $OS_VERSION\nK8S_FLAVOR: $K8S_FLAVOR\nEnvironment: $CANVOS_ENV\nISO Name: $ISO_NAME\n Image Repository: $IMAGE_REPOSITORY\n"
        read -p "Continue? (y/N): " -n 1 confirm
        echo
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Confirmed!"
            echo
            break
        else
            echo "Restarting..."
        fi
    else
        echo -e "OS_FLAVOR=$OS_FLAVOR\nK8S_FLAVOR: $K8S_FLAVOR\nEnvironment: $CANVOS_ENV\nISO Name: $ISO_NAME\nImage Repository: $IMAGE_REPOSITORY\n"
        read -p "Continue? (y/N): " -n 1 confirm
        echo
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Confirmed!"
            echo
            break
        else
            echo "Restarting..."
        fi
    fi
    
done
for v in "$@"; do
  k8s_version+="${arg}"
done

echo "Running command ./earthly.sh +build-all-images "${k8s_version[@]}" --OS_FLAVOR=${OS_FLAVOR} --OS_VERSION="${OS_VERSION/.04/}" \
    --K8S_FLAVOR=${K8S_FLAVOR} --CANVOS_ENV=${CANVOS_ENV} --ISO_NAME=${ISO_NAME} --IMAGE_REPOSITORY=${IMAGE_REPOSITORY}"
# Call a function with the variable arguments
./earthly.sh +build-all-images "${k8s_version[@]}" --OS_FLAVOR=${OS_FLAVOR} --OS_VERSION="${OS_VERSION/.04/}" \
    --K8S_FLAVOR=${K8S_FLAVOR} --CANVOS_ENV=${CANVOS_ENV} --ISO_NAME=${ISO_NAME} --IMAGE_REPOSITORY=${IMAGE_REPOSITORY}