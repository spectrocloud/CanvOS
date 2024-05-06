INSTRUCTIONS FOR USING YOUR OWN CA FOR SECURE BOOT KEYS
-------------------------------------------------------

1. First, create certificate requests for the PK, KEK and db certificates. Review the company information in the *.conf files, adjust `req_dn` section of each file to your liking, and then run:
```
openssl req -new -config PK_request.conf  -keyout PK.key  -out CSR_PK.req
openssl req -new -config KEK_request.conf -keyout KEK.key -out CSR_KEK.req
openssl req -new -config db_request.conf  -keyout db.key  -out CSR_db.req
```

2. This results in 3 .req files. Use these to request the certificates from the corporate CA.
3. Retrieve the issued certificates from the corporate CA in base64-encoded form (PEM format).

4. Save the retrieved certificate files as (note the case sensitivity):
PK.pem
KEK.pem
db.pem

5. Run `./earthly.sh +secure-boot-dirs` to create the secure-boot directory structure in CanvOS.
6. Place the files in the following directory structure:
```
CanvOS/
   secure-boot/
     private-keys/
       PK.key
       KEK.key
       db.key
     public-keys/
       PK.pem
       KEK.pem
       db.pem
```

7. Create the Full Disk Encryption key for the TPM:
```
openssl genrsa -out tpm2-pcr-private.pem 2048
```

8. Place the resulting `tpm2-pcr-private.pem` file in `secure-boot/private-keys`

9. Export the factory UEFI keys from your device by installing a regular Linux or Windows OS on the device. Then run the following commands to export the factory keys:
  * Linux:
  ```
  apt update && apt install -y efitools
  efi-readvar -v KEK -o KEK
  efi-readvar -v db -o db
  efi-readvar -v dbx -o dbx
  ```
  * Windows:
  ```
  Get-SecureBootUEFI –Name KEK –OutputFilePath KEK
  Get-SecureBootUEFI –Name db –OutputFilePath db
  Get-SecureBootUEFI –Name dbx –OutputFilePath dbx
  ```

10. Place the exported `KEK`, `db` and `dbx` files in the following directory structure:
```
CanvOS/
   secure-boot/
     exported-keys/
       KEK
       db
       dbx
```

11. Ensure your `.arg` file contains `UKI_BRING_YOUR_OWN_KEYS=true`

12. Run the "uki-genkey" function in CanvOS to generate the Secure Boot enrollment payload:
```
./earthly.sh +uki-genkey
```