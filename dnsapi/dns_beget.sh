#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_beget_info='Beget.com
Site: Beget.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_beget
Options:
 BEGET_User API user
 BEGET_Password API password
Issues: github.com/acmesh-official/acme.sh/issues/6200
Author: ARNik <arnik@arnik.ru>
'

Beget_Api="https://api.beget.com/api"

# API call function
_api_call() {
  api_url="$1"
  input_data="$2"
  url="$api_url?login=$Beget_Username&passwd=$Beget_Password&input_format=json&output_format=json"
  [ -n "$input_data" ] && url="${url}&input_data=$(echo -n "$input_data" | jq -s -R -r @uri)"

  echo "[DEBUG] _api_call url=$url"
  curl -s "$url"
}

# Add TXT record (supports multiple additions without overwriting)
dns_beget_add() {
  fulldomain=$1
  txtvalue=$2

  echo "[DEBUG] Starting dns_beget_add"
  echo "[DEBUG] fulldomain=$fulldomain"
  echo "[DEBUG] txtvalue=$txtvalue"

  Beget_Username="${Beget_Username:?Please set Beget_Username}"
  Beget_Password="${Beget_Password:?Please set Beget_Password}"

  fulldomain=$(echo "$fulldomain" | tr '[:upper:]' '[:lower:]')
  echo "[DEBUG] fulldomain (lowercase)=$fulldomain"

  # Get current DNS records
  res=$(_api_call "$Beget_Api/dns/getData" "{\"fqdn\":\"$fulldomain\"}") || {
    echo "[ERROR] API getData did not return a response"
    return 1
  }
  echo "[DEBUG] API getData response: $res"

  status=$(echo "$res" | jq -r '.answer.status' 2>/dev/null || echo "error")

  if [ "$status" = "success" ]; then
    old_txts=$(echo "$res" | jq -c '.answer.result.records.TXT // []')
    echo "[DEBUG] Existing TXT records from API: $old_txts"
  else
    echo "[WARN] Beget API error (status=$status). Try fallback with dig polling."

    old_txts="[]"
    i=1
    while [ $i -le 6 ]; do   # 6 раз по 20 секунд = максимум 120
      dig_txts=$(dig TXT +short "${fulldomain}" \
        @ns1.beget.com @ns2.beget.com | sed 's/^"//;s/"$//' | jq -R . | jq -s .)

      if [ "$dig_txts" != "[]" ]; then
        old_txts="$dig_txts"
        echo "[DEBUG] dig found TXT records on attempt $i: $old_txts"
        break
      else
        echo "[DEBUG] dig attempt $i: no TXT yet, waiting 20s..."
        if [ $i -gt 3 ]; then
          sleep 40
        else
          sleep 20
        fi
      fi

      i=$((i+1))
    done

    if [ "$old_txts" = "[]" ]; then
      echo "[DEBUG] dig found no TXT records after 120s. old_txts empty."
    fi
fi

  # Prepare new TXT record
  new_txt="{\"priority\":10,\"value\":\"$txtvalue\"}"
  echo "[DEBUG] New TXT record: $new_txt"

  # Merge with existing TXT records
  if [ "$old_txts" = "[]" ]; then
    txt_records="[$new_txt]"
  else
    old_objs=$(jq -c --argjson p 10 '[.[] | {priority: ($p|tonumber), value: .}]' <<< "$old_txts")
    txt_records=$(jq -c --argjson new "$new_txt" '. + [$new]' <<< "$old_objs")
  fi
  echo "[DEBUG] Final TXT records set: $txt_records"
  
  data="{\"fqdn\":\"$fulldomain\",\"records\":{\"TXT\":$txt_records}}"
  echo "[DEBUG] Sending data to changeRecords: $data"

  _api_call "$Beget_Api/dns/changeRecords" "$data" || {
    echo "[ERROR] Error calling changeRecords"
    return 1
  }

  echo "[INFO] TXT record successfully added for $fulldomain"
}

# Remove all _acme-challenge TXT records
dns_beget_rm() {
  fulldomain=$1

  echo "[DEBUG] Starting dns_beget_rm"
  echo "[DEBUG] fulldomain=$fulldomain"

  Beget_Username="${Beget_Username:?Please set Beget_Username}"
  Beget_Password="${Beget_Password:?Please set Beget_Password}"

  fulldomain=$(echo "$fulldomain" | tr '[:upper:]' '[:lower:]')
  echo "[DEBUG] fulldomain (lowercase)=$fulldomain"

  # Remove all TXT records by sending empty array
  data="{\"fqdn\":\"$fulldomain\",\"records\":{\"TXT\": []}}"
  echo "[DEBUG] Sending data to changeRecords: $data"

  _api_call "$Beget_Api/dns/changeRecords" "$data" || {
    echo "[ERROR] Error calling changeRecords"
    return 1
  }

  echo "[INFO] All _acme-challenge TXT records removed for $fulldomain"
}
