# SUSE Linux Enterprise Micro

## Pre-requisites :
* A host with SLES Micro distribution installed
* Registration code to register with SUSEConnect
* If you wish to override the BASE_IMAGE, make sure to use a container image that has zypper installed in it 

## Steps to build the image:
`./build.sh <REGISTRATION_CODE> [<BASE_IMAGE>]`