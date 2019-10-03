#!/bin/bash

# (C) Copyright 2008-2019 hSenid Software International (Pvt) Limited.
# All Rights Reserved.
# These materials are unpublished, proprietary, confidential source code of
# hSenid Software International (Pvt) Limited and constitute a TRADE SECRET
# of hSenid Software International (Pvt) Limited.
# hSenid Software International (Pvt) Limited retains all title to and intellectual
# property rights in these materials.

#getting the access token
# To get the Access token Enter below details.

#Enter client id (admin-cli) :
tclientId=admin-cli

#Enter username (admin) :
username=admin

# Enter password :
password=admin

# Enter client secret :
clientSecret=1b11187e-c3f3-44fd-a0e2-f0fd09ec4a66

# Enter grant_type (client_credentials):"
grantType=client_credentials

RESULT=$(curl -s --data "grant_type=${grantType}&client_id=${tclientId}&username=${username}&password=${password}&client_secret=${clientSecret}" https://devrincewind.hsenidmobile.com/auth/realms/rincewind/protocol/openid-connect/token)
TOKEN=$(echo $RESULT | sed 's/.*access_token":"//g' | sed 's/".*//g')

#validate inputs
stringValidator() {
  typeset locVarName
  typeset locVar
  locVarName=$1
  declare -n locVar=$1

  while true; do
    if [[ $locVar =~ " " ]]; then
      echo "It should not contain spaces"
      echo -n "Enter Again : "
      read locVar
      continue
    elif [[ $locVar =~ [^A-Za-z] ]]; then
      if [[ $locVarName =~ "claimValue" ]]; then
        if [[ $locVar =~ [^A-Za-z,] ]]; then
          echo "It should not contain special characters"
          echo -n "Enter Again : "
          read locVar
          continue
        else
          break
        fi
      fi
      echo "It should not contain special characters"
      echo -n "Enter Again : "
      read locVar
      continue
    elif [[ -z "$locVar" ]]; then
      echo "It can not be Empty!"
      echo -n "Enter : "
      read locVar
    else
      break

    fi
  done
}

#validate urls
urlValidator() {
  typeset locVarName
  typeset locVar
  locVarName=$1
  declare -n locVar=$1
  regex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
  while true; do
    if [[ $locVar =~ $regex ]]; then
      break
    else
      echo Link Not Valid!
      echo -n "Enter Again : "
      read locVar
    fi
  done
}

addClient() {
  echo -e "\nStarting Creating a Merchant..."
  echo "Enter below details"

  echo -e "\nMerchant-id :"
  read clientId
  stringValidator "clientId"

  echo -e "\nMerchant-name :"
  read clientName
  stringValidator "clientName"

  #create import.json file
  jq -c \
    --arg clientId "$clientId" \
    --arg clientName "$clientName" \
    '.clients[].clientId |= $clientId
     | .clients[].name |= $clientName     
  ' <add-client.json | jq . >import.json

  echo -e "\nMappers configuraion Starting"

  #append client mappers to json file
  declare -a mName=("Merchant Name" "Notification Url" "Default Bank" "Allowed Bank List")
  declare -a cName=("merchantName" "notificationUrl" "defaultBank" "allowedBankList")
  for i in {0..3}; do
    if [[ "${i}" == "0" ]]; then
      trimedClaimValue=$clientName
    elif [[ "${i}" == "1" ]]; then
      echo -e "\n${mName[i]} : "
      read claimValue
      urlValidator "claimValue"
      trimedClaimValue=$claimValue
    else
      echo -e "\n${mName[i]} : "
      read claimValue
      stringValidator "claimValue"
      trimedClaimValue=$(echo ${claimValue} | sed 's/,\s\+/,/g; s/\s\+,/,/g')
    fi
    jq --arg mappaerName "${mName[i]}" \
      --arg tokenClaimName "${cName[i]}" --arg claimValue "$trimedClaimValue" '.clients[0].protocolMappers += [
        {
          "name": $mappaerName,
          "protocol": "openid-connect",
          "protocolMapper": "oidc-hardcoded-claim-mapper",
          "consentRequired": false,
          "config": {
            "claim.value": $claimValue,
            "userinfo.token.claim": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": $tokenClaimName,
            "jsonType.label": "String"
          }
        }
      ]' <import.json >output.json
    mv output.json import.json
  done

  #import the json file to keycloak
  output=$(curl -s -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: bearer $1" --data @import.json https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/partialImport)
  echo -e "\nClient Added successfully...!"
}

viewClient() {
  viewClientId $1
  echo -e "\nEnter number :"
  read lineNo
  #get the id when line no is given
  clientId=$(sed -n "$lineNo{p;q;}" clients.txt | awk -F " " '{printf "%s%s",$2,ORS}')

  view=$(curl -s -H "Accept: application/json" -H "Authorization: bearer $1" https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients/${clientId})
  echo
  echo $view | jq . | jq -r '[.id, .clientId ] | @csv' | awk -v FS="," '{printf "%s%s\n%s%s\n%s","ID : ",$1,"Merchant ID : ",$2,ORS}'
  header="Mapper Name,Claim name,Claim Value"
  echo $header | cut -d',' --output-delimiter=$'\t\t' -f1-
  echo "============================================================"
  mapperName=$(echo $view | jq . | jq -r '[.protocolMappers[].name]' | sed 's/[][]//g' | tr -d '"')
  claimName=$(echo $view | jq . | jq -r '[.protocolMappers[].config."claim.name"]' | sed 's/[][]//g' | tr -d '"')
  claimValue=$(echo $view | jq . | jq -r '[.protocolMappers[].config."claim.value"]' | sed 's/[][]//g' | sed 's/\(.*\".*\),\(.*\".*\)/\1~\2/')

  paste <(echo $mapperName | cut -d',' --output-delimiter=$'\n' -f1-) <(echo $claimName | cut -d',' --output-delimiter=$'\n' -f1-) <(echo $claimValue | cut -d',' --output-delimiter=$'\n' -f1- | tr -d '"') | column -s $'\t' -t
  rm clients.txt
}

viewClientId() {
  findid=$(curl -s -H "Authorization: bearer $1" https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients?viewableOnly=true)
  echo $findid | jq . | jq -r '(.[] | [.clientId]) | @tsv' | nl |
    awk -v FS="," 'BEGIN{print "\tMerchant Name";print "================================"}{printf "%s%s",$1,ORS}'
  echo $findid | jq . | jq -r '(.[] | [.id, .clientId]) | @tsv' | nl |
    awk -v FS="," '{printf "%s\t%s%s",$1,$2,ORS}' >clients.txt
}

deleteClient() {
  viewClientId $1
  echo -e "\nEnter number :"
  read lineNo
  #get the id when line no is given
  clientId=$(sed -n "$lineNo{p;q;}" clients.txt | awk -F " " '{printf "%s%s",$2,ORS}')
  echo Are you sure you want to delete? [y/n]
  read answer
  if [[ $answer =~ "y" ]]; then
    delete=$(curl -s -X "DELETE" -H "Accept: application/json" -H "Authorization: bearer $1" https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients/${clientId})
    cliName=$(sed -n "$lineNo{p;q;}" clients.txt | awk -F " " '{printf "%s%s",$3,ORS}')
    echo $cliName deleted successfully...!
  else
    echo Exit.
  fi
  rm clients.txt
}

editClient() {
  viewClientId $1
  echo -e "\nEnter number :"
  read lineNo
  #get the id when line no is given
  clientId=$(sed -n "$lineNo{p;q;}" clients.txt | awk -F " " '{printf "%s%s",$2,ORS}')
  view=$(curl -s -H "Accept: application/json" -H "Authorization: bearer $1" https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients/${clientId})
  echo $view | jq . >edit-client.json

  while [ true ]; do
    echo -e '\n1 client-id \n2 client-name \n3 mappers \n'
    echo "Enter the number of option you want to edit, Exit(x)"
    read input
    case $input in
    1)
      output=$(jq '.clientId' edit-client.json)
      echo -e "\nCurrent Merchant Id :"$output
      echo "Enter the new value for Merchant Id"
      read newValue
      stringValidator "newValue"
      jq --arg newCliId "$newValue" '.clientId |= $newCliId' <edit-client.json >temp.json
      echo "clientId has changed!"
      mv temp.json edit-client.json
      continue
      ;;
    2)
      output=$(jq '.name' edit-client.json)
      echo -e "\nCurrent Merchant name :"$output
      echo "Enter the new value for Merchant name"
      read newValue
      stringValidator "newValue"
      jq --arg newValue "$newValue" '.name |= $newValue' <edit-client.json >temp.json
      echo "name has changed!"
      mv temp.json edit-client.json
      continue
      ;;
    3)
      output=$(jq '.protocolMappers' edit-client.json)
      echo $output | jq . | jq -r '.[] | [.name ] | @csv' | awk -v FS="," '{printf "%s%s",$1,ORS}' | nl | tr -d '"'
      echo $output | jq . | jq -r '.[] | [.id, .name ] | @csv' | awk -v FS="," '{printf "%s\t%s%s",$1,$2,ORS}' | nl >mapperId.txt
      echo -e "\nEnter number that you need to edit"
      read lineNo
      #get the id when line no is given
      mapperId=$(sed -n "$lineNo{p;q;}" mapperId.txt | awk -F " " '{printf "%s%s",$2,ORS}' | tr -d '"')     
      #echo $mapperId
      output1=$(jq --arg mapperId "$mapperId" '.protocolMappers | .[] | select(.id == $mapperId)' edit-client.json)
      echo 
      echo $output1 | jq . | jq -r ' [.id, .name, .config."claim.name", .config."claim.value" ] | @csv' | 
      sed 's/\(.*\".*\),\(.*\".*\)/\1~\2/' | awk -v FS="," '{printf "%s%s\n%s%s\n%s%s\n%s%s\n%s","Mapper ID : ",$1,"Mapper Name : ",$2,"Claim Name : ",$3,"Claim Value : ",$4,ORS}'

      echo -e '\n1 Mapper-name \n2 claim.name \n3 claim.value'
      echo "Enter the number of option you want to edit, Exit(x)"
      read option
      case $option in
      1)
        current=$(jq --arg mapperId "$mapperId" '.protocolMappers | .[] | select(.id == $mapperId).name' edit-client.json)
        echo -e "\nCurrent name : $current"
        echo Enter the mapper name you need to change
        read mapperName
        stringValidator "mapperName"
        current1=$(jq --arg mapperId "$mapperId" --arg mapperName "$mapperName" '(.protocolMappers[] | select(.id == $mapperId) | .name) |= $mapperName ' <edit-client.json >temp.json)
        mv temp.json edit-client.json
        echo Mapper name has changed!
        ;;
      2)
        current=$(jq --arg mapperId "$mapperId" '.protocolMappers | .[] | select(.id == $mapperId).config."claim.name"' edit-client.json)
        echo -e "\nCurrent claim.name : $current"
        echo Enter the claim.name you need to change
        read claimName
        stringValidator "claimName"
        current1=$(jq --arg mapperId "$mapperId" --arg claimName "$claimName" '(.protocolMappers[] | select(.id == $mapperId) | .config."claim.name") |= $claimName ' <edit-client.json >temp.json)
        mv temp.json edit-client.json
        echo claim.name has changed!
        ;;
      3)
        current=$(jq --arg mapperId "$mapperId" '.protocolMappers | .[] | select(.id == $mapperId).config."claim.value"' edit-client.json)
        echo -e "\nCurrent claim.value : $current"
        echo Enter the claim.value you need to change
        read claimValue
        stringValidator "claimValue"
        trimedClaimValue=$(echo ${claimValue} | sed 's/,\s\+/,/g; s/\s\+,/,/g')
        current1=$(jq --arg mapperId "$mapperId" --arg trimedClaimValue "$trimedClaimValue" '(.protocolMappers[] | select(.id == $mapperId) | .config."claim.value") |= $trimedClaimValue ' <edit-client.json >temp.json)
        mv temp.json edit-client.json
        echo claim.value has changed!
        ;;
      esac
      #update the mappers in keycloak
      jq --arg mapperId "$mapperId" '.protocolMappers | .[] | select(.id == $mapperId)' edit-client.json >mapperImport.json
      url=$(curl -s -X "PUT" -H "Content-Type: application/json;charset-UTF-8" -H "Accept: application/json" -H "Authorization: bearer $1" --data @mapperImport.json https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients/${clientId}/protocol-mappers/models/${mapperId})
   
      rm mapperImport.json
      continue
      ;;
    x)
      break
      ;;
    esac
  done

  echo "Are you sure you want to submit [y/n]"
  read response

  if [ "$response" = "y" ]; then
    update=$(curl -s -X "PUT" -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: bearer $1" --data @edit-client.json https://devrincewind.hsenidmobile.com/auth/admin/realms/rincewind/clients/${clientId})
    echo $clientId updated successfully...!
  else
    echo unknown command
  fi
}

echo "Select an option to manage Merchant."
echo -e "Add Merchant [a] \nEdit Merchant [e] \nView Merchant [v] \nDelete Merchant [d]"
while [ true ]; do
  read input
  case $input in
  a)
    addClient $TOKEN
    break
    ;;
  v)
    viewClient $TOKEN
    break
    ;;
  d)
    deleteClient $TOKEN
    break
    ;;
  e)
    editClient $TOKEN
    break
    ;;
  *)
    echo Unrecognized response
    break
    ;;
  esac
done
