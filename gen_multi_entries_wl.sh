#!/bin/bash

start=`date +%s`
# usage menu
echo
echo "---------------------- Usage ----------------------"
echo -e "\n   bash $0\n\n    -n < number of entries > \n    -t < list type > (WI or WL) \n    -s < service provider code > (ex. 151) \n    -a < APDUIdentifier code > \n    -u < ADUIdentifer code > \n    -e < exceptionListVersion code > \n    -p < progressive WL filename > \n"



while getopts n:t:s:a:u:e:p: flag
do
    case "${flag}" in
		n) n=${OPTARG};;
        t) LIST_TYPE=${OPTARG};;
        s) S_PROVIDER=${OPTARG};;
        a) C_APDU=${OPTARG};;
        u) C_ADU_IDE=${OPTARG};;
        e) C_EXC_VRS=${OPTARG};;
        p) fn_PRG_WL=${OPTARG};;
		\?) echo -e "\n Argument error! \n"; exit 0 ;;
	esac
done

echo -e "--------------------------------------------------- \n"

# params check
if [ $# != 14 ] ; then
    echo "Argument error: please digit right command."
	echo
	exit 0
fi

OUT_DIR="OUT_DIR_WL"
# create OUT_DIR if not exist
if ! [ -d $OUT_DIR ] ; then
	mkdir $OUT_DIR
	path_OUT_dir=$(realpath $OUT_DIR)
    echo -e "...create '$OUT_DIR' at path: '$path_OUT_dir' \n"
    chmod 0777 "$path_OUT_dir"
else
	path_OUT_dir=$(realpath $OUT_DIR)
fi


tmp_filename_WL="tmp_filename_white_list.xml"
min_pan=1000000000000000000
max_pan=9999999999999999999
pad_f='F'
min_plate=100
max_plate=999
providers_code=('151' '2321' '3000' '7' '49')
naz_providers=('IT' 'IT' 'IT' 'DE' 'FR')
T_CHARGER='6'
keys=( {A..Z} )
values=('11000' '10011' '01110' '10010' '10000' '10110' '01011' '00101' '01100' '11010' '11110' '01001' '00111' # baudot encoding
        '00110' '00011' '01101' '11101' '01010' '10100' '00001' '11100' '01111' '11001' '10111' '10101' '10001') 


# input validation
if [[ $LIST_TYPE != 'WI' ]] && [[ $LIST_TYPE != 'WF' ]] ; then
    echo -e "Param error: please digit a valid type of white list (WI or WF) \n"
    exit 0

elif ! [[ ${providers_code[@]} =~ $S_PROVIDER ]] ; then
    echo -e "Param error: service provider's code '$S_PROVIDER' doesn't exist. \n"
    exit 0
elif [ $T_CHARGER != '6' ] ; then 
    echo -e "Param error: toll charger must be 6 \n"
    exit 0
fi

# functions
function generate_PAN
{   
    PAN=$(shuf -i $min_pan-$max_pan -n 1)$pad_f
    echo ${PAN} 
}

function generate_PLATE_NUMBER
{
    first_C=$(tr -dc A-Z </dev/urandom | head -c 2)
    num=$(shuf -i $min_plate-$max_plate -n 1)
    second_C=$(tr -dc A-Z </dev/urandom | head -c 2)
    PLATE=$first_C$num$second_C
    echo ${PLATE}
}

function convert_PLATE_to_HEX 
{
    plate=$1
    pad_plate="07"
    hex_plate="$(printf '%s' "$plate" | xxd -p -u)"
    hex_plate=$pad_plate$hex_plate
    echo ${hex_plate}
}

function extract_WL_type 
{
    LIST_TYPE=$1
    if [ $LIST_TYPE == "WI" ] ; then
        LIST_TYPE="WIWI"
    else
        LIST_TYPE="WFWF"
    fi
    echo ${LIST_TYPE}
}

function extract_offset_pad 
{
    code=$1
    length_code=$2
    pad_num="0"
    offset=$(expr $length_code - ${#code})
    while [ ${#final_code} != $offset ] 
    do
        final_code=$final_code$pad_num
    done
    final_code=$final_code$code
    echo ${final_code}
}

function get_naz_from_pvd
{
    pvd=$1
    echo ${hash_PVD_NAZ[$pvd]}
}

function generate_BAUDOT
{
    NAZ=$1
    first_ch=${NAZ:0:1}
    second_ch=${NAZ:1:1}
    first_baudot=${hash_baudot[$first_ch]}
    second_baudot=${hash_baudot[$second_ch]}
    baudot_code=$first_baudot$second_baudot
    echo ${baudot_code}
}

declare -A hash_PVD_NAZ
length=${#providers_code[@]}

for ((i=0; i<$length; i++)) ; do
	hash_PVD_NAZ["${providers_code[i]}"]="${naz_providers[i]}"
done

declare -A hash_baudot
length=${#keys[@]}

for ((i=0; i<$length; i++)) ; do
	hash_baudot["${keys[i]}"]="${values[i]}"
done

NAZ_S_PROVIDER=$(get_naz_from_pvd $S_PROVIDER)
BAUDOT_CODE=$(generate_BAUDOT $NAZ_S_PROVIDER)
LIST_TYPE=$(extract_WL_type $LIST_TYPE)

# generate white list file
cat << EOF > "$path_OUT_dir/$tmp_filename_WL"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<infoExchange>
	<infoExchangeContent>
		<apci>
			<aidIdentifier>3</aidIdentifier>
			<apduOriginator>
				<countryCode>${BAUDOT_CODE}</countryCode>
				<providerIdentifier>${S_PROVIDER}</providerIdentifier>
			</apduOriginator>
			<informationSenderId>
				<countryCode>${BAUDOT_CODE}</countryCode>
				<providerIdentifier>${S_PROVIDER}</providerIdentifier>
			</informationSenderId>
			<informationRecipientId>
				<countryCode>0110000001</countryCode>
				<providerIdentifier>${T_CHARGER}</providerIdentifier>
			</informationRecipientId>
			<apduIdentifier>${C_APDU}</apduIdentifier>
			<apduDate>20230316175200Z</apduDate>
		</apci>
		<adus>
			<exceptionListAdus>
				<ExceptionListAdu>
					<aduIdentifier>${C_ADU_IDE}</aduIdentifier>
					<exceptionListVersion>${C_EXC_VRS}</exceptionListVersion>
					<exceptionListType>12</exceptionListType>
					<exceptionValidityStart>20230203085452Z</exceptionValidityStart>
					<exceptionListEntries>
EOF

for ((i=0; i<n; i++)) 
do
    echo -e "...generating entry: $(expr $i + 1)\n"
    PAN=$(generate_PAN)
    PLATE=$(generate_PLATE_NUMBER)
    HEX_PLATE=$(convert_PLATE_to_HEX $PLATE)
    cat << EOF >> "$path_OUT_dir/$tmp_filename_WL"
                        <ExceptionListEntry>
							<userId>
								<pan>${PAN}</pan>
								<licencePlateNumber>
									<countryCode>0110000001</countryCode>
									<alphabetIndicator>000000</alphabetIndicator>
									<licencePlateNumber>${HEX_PLATE}</licencePlateNumber>
								</licencePlateNumber>
							</userId>
							<statusType>0</statusType>
							<reasonCode>0</reasonCode>
							<entryValidityStart>20230104140028Z</entryValidityStart>
							<actionRequested>3</actionRequested>
							<efcContextMark>
								<contractProvider>
									<countryCode>${BAUDOT_CODE}</countryCode>
									<providerIdentifier>${S_PROVIDER}</providerIdentifier>
								</contractProvider>
								<typeOfContract>001D</typeOfContract>
								<contextVersion>9</contextVersion>
							</efcContextMark>
						</ExceptionListEntry>
EOF
done

cat << EOF >> "$path_OUT_dir/$tmp_filename_WL"             
					</exceptionListEntries>
				</ExceptionListAdu>
			</exceptionListAdus>
		</adus>
	</infoExchangeContent>
</infoExchange>
EOF

# pattern filename WL:F<naz_SP>00<cod_SP(5 chars)>T<naz_TC>00<cod_TC (5 chars)>.SET.<list_TYPE>.000<PRG (10 chars)>.XML
const_F="F"
naz_TC="IT"
const_T="T"
const_SET="SET"
fn_S_PROVIDER=$(extract_offset_pad $S_PROVIDER 5)
fn_T_CHARGER=$(extract_offset_pad $T_CHARGER 5)
fn_PRG_WL=$(extract_offset_pad $fn_PRG_WL 10)
filename_WL="$const_F$NAZ_S_PROVIDER$fn_S_PROVIDER$const_T$naz_TC$fn_T_CHARGER.$const_SET.$LIST_TYPE.$fn_PRG_WL.XML"
mv "$path_OUT_dir/$tmp_filename_WL" "$path_OUT_dir/$filename_WL"

echo -e "--------------------------------------------------- \n"

end=`date +%s`
echo -e "...execution time: `expr $end - $start` seconds. \n"
echo -e "...file presents at path: '$path_OUT_dir' \n"