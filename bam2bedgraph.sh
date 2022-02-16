#!/bin/bash

#/ Convert BAM files to bedGraphs

set -e -o pipefail
LC_ALL=C

export VERSION=1.0.1

#/ Help section:
usage(){
  echo "

## Bam2Bigwig.sh Version: ${VERSION}

=> Options:
   
------------------------------------------------------------------------------------------------------------------
-h | --help          : show this message                                                           {}
-b | --bams          : space-delimited string of input bam files in double quotes or *.bam         {}
-m | --mode          : <single> or <paired>, if paired will use -pc option in bedtools genomecov   {}
-a | --atacseq       : ATAC-seq mode, will use cutsites rather than reads                          {FALSE}
-e | --extend        : numeric value to extend reads to fragment size, see details                 {0}
-n | --normalize     : if set then normalizes data based on the scaling_factors.txt file           {FALSE}
-j | --njobs         : number of parallel (GNU parallel) jobs to create bedGraphs, see details.    {1}
-q | --sortthreads   : number of threads for sorting the bedGraph                                  {1}
-w | --sortmem       : memory for sorting the bedGraph                                             {1G}
-t | --nobigwig      : if set then do not output bigwig files along with the bedGraphs             {FALSE}
-g | --average       : if set then average samples of the same group, see details                  {FALSE}
------------------------------------------------------------------------------------------------------------------

Details: * Option --extend is simply -fs in bedtools genomecov. If --atacseq is set then this can be
           used to smooth the coverage of the cutting sites for visualization. It will then use
           bedtools slop -b to extend the cutting sites to both directions, so if a 100bp window is
           desired for smoothing one should set it to 50 to have 50bp extension to each direction.
           
         * Option --normalize will make use of the scaling_factors.txt file which must be present in the same 
           directory. This file must have $1 with the exact file names (of the bam files) and $2 a scaling factor, 
           e.g. from DESeq2 which will be used to divide the raw counts (so 4th column of bedGraph file) by.
           
         * Option --njobs is -j of GNU parallel. One job requires up to 5 threads depending on whether --atacseq is 
           set or not plus the --sortthreads which are the threads for sorting the bedGraphs so be sure to set this 
           rather higher than lower. Memory requirement is basically what the sort (--sortmem) needs, everything +
           else is mostly simple file/text parsing operations.

         * By default all all .bedGraph files in the directory will be also written to bigwig. Set --nobigwig to 
           turn that off. As this is a simple script that does not know whether a bedGraph that is in the directory 
           comes from this script or just happens to be there from any other process it is recommended to make a 
           separate directory for every run of this script and simply symlink the bam files into it to have a clean 
           environment.

         * Towards --average: If samples are named as group_rep1*, _rep2*, rep3* etc so using '_rep' as first 
           delimiter after the groupwise basename and --average is set then all bedGraph files of that group 
           will be averaged. If no "_rep" is found then this is deactivated regardless whether it is set or not.

"
}; if [[ -z "$1" ]] || [[ $1 == -h ]] || [[ $1 == --help ]]; then usage; exit; fi

#------------------------------------------------------------------------------------------------------------------------

#/ Set args:
for arg in "$@"; do                         
 shift                                      
 case "$arg" in
   "--bams")          set -- "$@" "-b"    ;;   
   "--mode")          set -- "$@" "-m"    ;;   
   "--atacseq")       set -- "$@" "-a"    ;;   
   "--extend")        set -- "$@" "-e"    ;;   
   "--normalize")     set -- "$@" "-n"    ;;   
   "--njobs")         set -- "$@" "-j"    ;;   
   "--sortthreads")   set -- "$@" "-q"    ;;   
   "--sortmem")       set -- "$@" "-w"    ;;  
   "--nobigwig")      set -- "$@" "-t"    ;;   
   "--average")       set -- "$@" "-g"    ;;   
   *)                 set -- "$@" "$arg"  ;;   
 esac
done

#/ Set defaults and check sanity:
bams=""
mode=""
atacseq="FALSE"
extend="0"
normalize="FALSE"
njobs="1"
sortthreads="1"
sortmem="1G"
nobigwig="FALSE"
average="FALSE"

echo ''

#/ getopts and export:
while getopts b:m:e:j:q:w:antg OPT           
  do   
  case ${OPT} in
    b) bams="${OPTARG}"          ;;
    m) mode="${OPTARG}"          ;;
    a) atacseq="TRUE"            ;;
    e) extend="${OPTARG}"        ;;
    n) normalize="TRUE"          ;;
    j) njobs="${OPTARG}"         ;;
    q) sortthreads="${OPTARG}"   ;;
    w) sortmem="${OPTARG}"       ;;
    t) nobigwig="TRUE"           ;;
    g) average="TRUE"            ;;
  esac
done	

if [[ "${bams}" == "" ]]; then
  echo 'Either --bam or --bigwig must be specified'
  exit 1
fi

if [[ "${mode}" != "single" ]] && [[ "${mode}" != "paired" ]]; then
    if [[ "${atacseq}" == "FALSE" ]]; then
        echo 'Argument --mode must be specified and must be <single> or <paired>'
        exit 1
    fi    
fi

if [[ "${atacseq}" == "TRUE" ]]; then
    if [[ "${mode}" == "paired" ]]; then
        echo '[Info] --atacseq is set, setting --mode to single to use cutsites rather than reads'
        mode='single'
    fi   
fi

OPTS=(bams mode extend njobs atacseq \
      normalize sortthreads sortmem customsuffix)
for i in ${OPTS[*]}; do export $i; done

#/ Print summary:

echo ''
echo '---------------------------------------------------------------------------------------------'
echo '[Version] ::: '"${VERSION}"
echo ''
echo '[Info] Running with these parameters:'
echo '       --bams          = '"${bams}"
echo '       --mode          = '"${mode}"
echo '       --extend        = '"${extend}"
echo '       --njobs         = '"${njobs}"
echo '       --atacseq       = '"${atacseq}"
echo '       --normalize     = '"${normalize}"
echo '       --sortthreads   = '"${sortthreads}"
echo '       --sortmem       = '"${sortmem}"
echo '       --nobigwig      = '"${nobigwig}"
echo '       --average       = '"${average}"
echo '---------------------------------------------------------------------------------------------'
echo ''

#------------------------------------------------------------------------------------------------------------------------

#/ Function that checks if required tools are callable:
function PathCheck {
  
  if [[ $(command -v $1 | wc -l | xargs) == 0 ]]; then 
  echo ${1} >> missing_tools.txt
  fi
  
}; export -f PathCheck

Tools=(bedtools mawk parallel samtools)

#/ if that argument is set check for tools, then exit:
if [[ -e missing_tools.txt ]]; then rm missing_tools.txt; fi

for i in $(echo ${Tools[*]}); do PathCheck $i; done

if [[ -e missing_tools.txt ]]; then 
  echo '[Error] Tools missing in PATH, see missing_tools.txt'
  exit 1
fi 

#/ If --normalize then scaling_factors.txt must be present:
if [[ "${normalize}" == "TRUE" ]]; then
  if [[ ! -e scaling_factors.txt ]]; then
    echo 'Argument --normalize is set but no file <scaling_factors.txt> can be found!'
    exit 1
  fi
fi  

#------------------------------------------------------------------------------------------------------------------------

#/ Function to produce BigWig from Bam:
function Bam2Bw {
  
  #/ Input is one bam file per sample:
  singlebam="${1}"
  
  Basename=${singlebam%.bam}
  
  #/ Get chromsizes based on idxstats
  samtools view -H "${singlebam}" | grep 'SN:' | cut -f2,3 | awk '{gsub("SN:|LN:", "");print}' > "${singlebam}".chromsize
  
  #---------------------------------------------
    
  #/ Normalize by using the scaling factors from scaling_factors.txt
  if [[ "${normalize}" == "TRUE" ]]; then
  
    #/ take the reciprocal since the scale factor is intended for division but genomecov multiplies:
    SF=$(bc <<< "scale=10; $(grep -w ${singlebam} scaling_factors.txt | cut -f2)^-1")
    
    if [[ "${SF}" == "" ]]; then
      echo "[Error]" "${singlebam}" "not found in scaling_factors.txt"
      exit 1
    fi
    
  else SF=1
  fi
  
  #---------------------------------------------
  
  #/ function to get cutsites in case of --atacseq
  getCutsite() { 
  
    if (( $(head -n1 $1 | awk -F'\t' 'NR==1{print NF}') < 6 ));
      then
      echo '[Error]' $1 "has fewer than six columns!"
      exit 1
    fi
    
    mawk 'OFS="\t" {if ($6 == "+") print $1,$2+4,$2+5,".",".",$6} 
                   {if ($6 == "-") print $1,$3-5,$3-4,".",".",$6}' $1
                   
  }
  
  #---------------------------------------------
  
  #/ chain the commands into a generic call:
  if [[ "${atacseq}" == "TRUE" ]]; then
  
    do_bamtobed='bedtools bamtobed -i "${singlebam}" | getCutsite /dev/stdin |'
    
    if [[ "${extend}" != 0 ]]; then 
    
      do_slop='bedtools slop -g "${singlebam}".chromsize -b "${extend}" -i - |'
      suffix='_extended'
      
    else do_slop=''; suffix=''
      
    fi  
    
    input='-i -'
    csize='-g "${singlebam}".chromsize'
    is_paired=''
    
  else
  
    do_bamtobed=''
    do_slop=''
    input='-ibam "${singlebam}"'
    csize=''
    
    if [[ "${extend}" != 0 ]]; then 
      do_extend='-fs "${extend}"'
      suffix='_extended'
    else 
      do_extend=''
      suffix=''
    fi  
    
    if [[ "${mode}" == "paired" ]]; then is_paired='-pc'; else is_paired=''; fi
    
  fi

  do_scale='-scale "${SF}"'
  
  #/ put it together:
  eval \
  "${do_bamtobed}" \
  "${do_slop}" \
  bedtools genomecov -bga "${input}" "${csize}" "${do_extend}" "${is_paired}" "${do_scale}" \
  | sort -k1,1 -k2,2n --parallel="${sortthreads}" -S "${sortmem}" > "${Basename}""${suffix}".bedGraph
    
  export sfx=123

}; export -f Bam2Bw

#/ function for optional averaging:
function AveragebedGraph {

    bedtools unionbedg -i $(ls "${1}"*.bedGraph | tr "\n" " ") \
    | mawk 'OFS="\t" {sum=0; for (col=4; col<=NF; col++) sum += $col; print $1, $2, $3, sum/(NF-4+1); }'

}; export -f AveragebedGraph

#-----------------------------------------------

#/ to bedGraph
echo ${bams} | tr " " "\n" | mawk NF | sort -u | parallel --will-cite -j "${njobs}" "Bam2Bw {}"

#/ optionally average if "_rep" nomenclature:
if [[ "${extend}" != 0 ]]; then 
    suffix='_extended'
else   
    suffix=''
fi    

if [[ "${average}" == "TRUE" ]]; then

    if [[ $(find . -maxdepth 1 -name "*_rep*" | wc -l) == 0 ]]; then
        echo '[Info] --average is set but no bedGraphs with *_rep*  as delimiter can be found -- continuing without that option'
    else 
        find . -maxdepth 1 -name "*_rep*.bedGraph" \
        | awk -F "_rep" '{print $1 | "sort -u"}' \
        | parallel --will-cite -j "${njobs}" "AveragebedGraph {}_rep > {}${suffix}_averaged.bedGraph"   

    fi    
fi    


#/ optionally (by default true) to bigwig
if [[ "${nobigwig}" == "FALSE" ]]; then

    ls *chromsize | head -n 1 | xargs cat > chromsizes_tobigwig.txt

    if [[ $(cat chromsizes_tobigwig.txt | wc -l) == 0 ]]; then 
        echo '[Error] Cannot create bigwigs as chromsize file cannot be parsed'
        exit 1
    fi   

    ls *.bedGraph | parallel --will-cite  -j "${njobs}" "bedGraphToBigWig {} chromsizes_tobigwig.txt {.}.bigwig"

fi
