# az-infra-mgmt

``` bash
base64data=$(cat base64.txt)
{
  echo "-----BEGIN CERTIFICATE-----"
  echo "$base64data"
  echo "-----END CERTIFICATE-----"
} > mycert.crt
```
