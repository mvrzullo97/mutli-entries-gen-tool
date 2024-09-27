#!/bin/bash

start=`date +%s`
# usage menu
echo
echo "---------------------- Usage ----------------------"
echo -e "\n   bash $0\n\n    -ne < Number of entries > \n    -sp < Service Provider code > \n    -ap < APDU code > \n    -tc < Type of Contract > \n    -cv < Context version > \n    -ad < DIDI ADU code (opt.) > \n    -ed < DIDI exceptionListVersion (opt.) > \n    -ds < Discount ID (opt.) > \n    -pd < DIDI progressive filename (opt.) > \n    -wt < WLWL type > (WI or WL) \n    -aw < WLWL ADU code > \n    -ew < WLWL exceptionListVersion > \n    -pw < WLWL progressive filename > \n    -sv < save Pan-Targa (t/f opt.) >  \n"


# to do 
#1) salvare le n coppie in un file di testo se argomento = TRUE
#2) generare una WL di cambio targa


counter_args=0

# parsing degli OPTARGS
while [[ "$#" -gt 0 ]] ; do
    case $1 in
        -ne) n="$2"
			((counter_args++))
			 	shift 2;;
		-wt) LIST_TYPE="$2"
			((counter_args++))
			 	shift 2;;
        -sp) S_PROVIDER="$2"
			((counter_args++))
			 	shift 2;;
		-ap) C_APDU="$2"
			((counter_args++))
				shift 2;;
		-tc) CONTRACT_TYPE="$2"
			((counter_args++))
				shift 2;;
		-cv) CONTEXT_VERSION="$2"
			((counter_args++))
				shift 2;;
		-ds) DISCOUNT="$2"
			((counter_args++))
			 	shift 2;;
		-ad) C_ADU_IDE_DI="$2"
			((counter_args++))
				shift 2;;
		-ed) C_EXC_VRS_DI="$2"
			((counter_args++))
			 	shift 2;;
		-pd) fn_PRG_DI="$2"
			((counter_args++))
			 	shift 2;;
		-aw) C_ADU_IDE_WL="$2"
			((counter_args++))
				shift 2;;
		-ew) C_EXC_VRS_WL="$2"
			((counter_args++))
			 	shift 2;;
		-pw) fn_PRG_WL="$2"
			((counter_args++))
			 	shift 2;;
		-sv) save_txt="$2"
			((counter_args++))
			 	shift 2;;
        *)  echo -e "Error: Invalid option $1\n"
			exit 0
    esac
done

echo -e "--------------------------------------------------- \n"

if [ $counter_args != 9 ] && [ $counter_args != 10 ] && [ $counter_args != 13 ] && [ $counter_args != 14 ] ; then
	echo "Argument error: please digit right command."
	echo
	exit 0
fi

OUT_DIR="OUT_DIR"
if ! [ -d $OUT_DIR ] ; then
	mkdir $OUT_DIR
	path_OUT_dir=$(realpath $OUT_DIR)
    echo -e "...create '$OUT_DIR' at path: '$path_OUT_dir' \n"
    chmod 0777 "$path_OUT_dir"
else
	path_OUT_dir=$(realpath $OUT_DIR)
fi

file_couple="Pan_Targa_couples.xml"

if [ -f $file_couple ] ; then
> $file_couple
fi

# save Pan-Targa into file .xml
if [ $save_txt == 't' ] ; then
	touch $file_couple
	chmod 0777 $file_couple
	echo -e "...create '$file_couple' at path: '$(realpath $file_couple)'\n"
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

if [[ $LIST_TYPE != 'WI' ]] && [[ $LIST_TYPE != 'WF' ]] ; then
    echo -e "Param error: please digit a valid type of White List (WI or WF) \n"
    exit 0

elif ! [[ ${providers_code[@]} =~ $S_PROVIDER ]] ; then
    echo -e "Param error: Service Provider's code '$S_PROVIDER' doesn't exist. \n"
    exit 0
fi

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

if ! [ -z "${DISCOUNT}" ] ; then
    BOOL_discount=true
	tmp_filename_DI="tmp_filename_discount_incremental.xml"
fi

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

if [ $BOOL_discount ] ; then
cat << EOF > "$path_OUT_dir/$tmp_filename_DI"
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
					<aduIdentifier>${C_ADU_IDE_DI}</aduIdentifier>
					<exceptionListVersion>${C_EXC_VRS_DI}</exceptionListVersion>
					<exceptionListType>12</exceptionListType>
					<exceptionValidityStart>20230203085452Z</exceptionValidityStart>
					<exceptionListEntries>
EOF
((C_APDU++))
fi

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
					<aduIdentifier>${C_ADU_IDE_WL}</aduIdentifier>
					<exceptionListVersion>${C_EXC_VRS_WL}</exceptionListVersion>
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

	if [ $save_txt == 't' ] ; then
		cat << EOF >> "$(realpath $file_couple)"
$i)$PAN-$HEX_PLATE-
EOF
	fi

    cat << EOF | tee -a "$path_OUT_dir/$tmp_filename_DI" "$path_OUT_dir/$tmp_filename_WL" > /dev/null 2>&1
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
								<typeOfContract>${CONTRACT_TYPE}</typeOfContract>
								<contextVersion>${CONTEXT_VERSION}</contextVersion>
							</efcContextMark>
EOF
if [ $BOOL_discount ] ; then
cat << EOF | tee -a "$path_OUT_dir/$tmp_filename_DI" "$path_OUT_dir/$tmp_filename_WL" >> /dev/null
                            <applicableDiscounts>
                                <discountId>${DISCOUNT}</discountId>
                            </applicableDiscounts>
EOF
fi

cat << EOF | tee -a "$path_OUT_dir/$tmp_filename_DI" "$path_OUT_dir/$tmp_filename_WL" > /dev/null 2>&1
						</ExceptionListEntry>
EOF
done

cat << EOF | tee -a "$path_OUT_dir/$tmp_filename_DI" "$path_OUT_dir/$tmp_filename_WL" > /dev/null 2>&1       
					</exceptionListEntries>
				</ExceptionListAdu>
			</exceptionListAdus>
		</adus>
	</infoExchangeContent>
</infoExchange>
EOF

const_F="F"
naz_TC="IT"
const_T="T"
const_SET="SET"
fn_S_PROVIDER=$(extract_offset_pad $S_PROVIDER 5)
fn_T_CHARGER=$(extract_offset_pad $T_CHARGER 5)

if [ $BOOL_discount ] ; then
	const_DIDI="DIDI"
	fn_PRG_DI=$(extract_offset_pad $fn_PRG_DI 10)
	filename_DI="$const_F$NAZ_S_PROVIDER$fn_S_PROVIDER$const_T$naz_TC$fn_T_CHARGER.$const_SET.$const_DIDI.$fn_PRG_DI.XML"
	mv "$path_OUT_dir/$tmp_filename_DI" "$path_OUT_dir/$filename_DI"
fi

fn_PRG_WL=$(extract_offset_pad $fn_PRG_WL 10)
filename_WL="$const_F$NAZ_S_PROVIDER$fn_S_PROVIDER$const_T$naz_TC$fn_T_CHARGER.$const_SET.$LIST_TYPE.$fn_PRG_WL.XML"
mv "$path_OUT_dir/$tmp_filename_WL" "$path_OUT_dir/$filename_WL"

echo -e "--------------------------------------------------- \n"

end=`date +%s`
echo -e "...execution time: `expr $end - $start` seconds.\n"
echo -e "...files present at path: '$path_OUT_dir' \n"