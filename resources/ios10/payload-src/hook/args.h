
typedef struct Boot_Video {
    unsigned long    v_baseAddr;    /* Base address of video memory */
    unsigned long    v_display;    /* Display Code (if Applicable */
    unsigned long    v_rowBytes;    /* Number of bytes per pixel row */
    unsigned long    v_width;    /* Width */
    unsigned long    v_height;    /* Height */
    unsigned long    v_depth;    /* Pixel Depth and other parameters */
} Boot_Video;

typedef struct boot_args {
    uint16_t        Revision;            /* Revision of boot_args structure */
    uint16_t        Version;            /* Version of boot_args structure */
    uint32_t        virtBase;            /* Virtual base of memory */
    uint32_t        physBase;            /* Physical base of memory */
    uint32_t        memSize;            /* Size of memory */
    uint32_t        topOfKernelData;    /* Highest physical address used in kernel data area */
    Boot_Video        Video;                /* Video Information */
    uint32_t        machineType;        /* Machine Type */
    void            *deviceTreeP;        /* Base of flattened device tree */
    uint32_t        deviceTreeLength;    /* Length of flattened tree */
    char            CommandLine[255];    /* Passed in command line */
    uint32_t        bootFlags;        /* Additional flags specified by the bootloader */
    uint32_t        memSizeActual;        /* Actual size of memory */
} boot_args;
