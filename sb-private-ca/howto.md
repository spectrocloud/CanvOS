INSTRUCTIONS FOR USING YOUR OWN CA FOR SECURE BOOT KEYS
-------------------------------------------------------

1. First, create certificate requests for the PK, KEK and db certificates:
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

5. Create a `secure-boot` directory in CanvOS.
6. Place the files in the following directory structure:
```
CanvOS/
   secure-boot/
     private-keys/
       PK.pem
       KEK.key
       db.key
     public-keys/
       PK.pem
       KEK.pem
       db.pem
```

7. Run the "uki-genkey" function in CanvOS to generate the Secure Boot enrollment payload:
```
./earthly +uki-genkey
```