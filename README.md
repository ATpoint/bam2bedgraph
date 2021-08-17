# bam2bedgraph

A simple bash script to convert bam files to bedGraph and bigwig files.  

Run bash script without arguments to see options:

```bash

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
           directory. This file must have  with the exact file names (of the bam files) and  a scaling factor, 
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
           will be averaged. If no _rep is found then this is deactivated regardless whether it is set or not.

```           

**Examples**

- for single-end data, extending reads to fragments of 200bp:
  `./bam2bedgraph.sh --bams "*.bam" --mode single --extend 200`
  
- for ATAC-seq data, reducing reads to cutting sites:
  `./bam2bedgraph.sh --bams "*.bam" --atacseq` 
  
- for ATAC-seq data, smoothing the cutting sites with a 100bp window (=2*50bp):
  `./bam2bedgraph.sh --bams "*.bam" --atacseq --extend 50` 
 
<br>
<br>
Docker image at https://hub.docker.com/r/atpoint/bam2bigwig or use the conda environment at this repo.
