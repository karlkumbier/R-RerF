#' RerF forest Generator
#'
#' Creates a decision forest based on an input matrix and class vector.  This is the main function in the rerf package.
#'
#' @param X an n by d numeric matrix (preferable) or data frame. The rows correspond to observations and columns correspond to features.
#' @param Y an n length vector of class labels.  Class labels must be integer or numeric and be within the range 1 to the number of classes.
#' @param min.parent the minimum splittable node size.  A node size < min.parent will be a leaf node. (min.parent = 6)
#' @param trees the number of trees in the forest. (trees=100)
#' @param max.depth the longest allowable distance from the root of a tree to a leaf node (i.e. the maximum allowed height for a tree).  If max.depth=0, the tree will be allowed to grow without bound.  (max.depth=0)  
#' @param bagging a non-zero value means a random sample of X will be used during tree creation.  If replacement = FALSE the bagging value determines the percentage of samples to leave out-of-bag.  If replacement = TRUE the non-zero bagging value is ignored. (bagging=.2) 
#' @param replacement if TRUE then n samples are chosen, with replacement, from X. (replacement=TRUE)
#' @param stratify if TRUE then class sample proportions are maintained during the random sampling.  Ignored if replacement = FALSE. (stratify = FALSE).
#' @param fun a function that creates the random projection matrix. (fun=NULL) 
#' @param mat.options a list of parameters to be used by fun. (mat.options=c(ncol(X), round(ncol(X)^.5),1L, 1/ncol(X)))
#' @param rank.transform if TRUE then each feature is rank-transformed (i.e. smallest value becomes 1 and largest value becomes n) (rank.transform=FALSE)
#' @param store.oob if TRUE then the samples omitted during the creation of a tree are stored as part of the tree.  This is required to run OOBPredict(). (store.oob=FALSE)
#' @param store.ns if TRUE then the number of training observations at each node is stored. This is required to run FeatureImportance() (store.ns=FALSE)
#' @param progress if TRUE then a pipe is printed after each tree is created.  This is useful for large datasets. (progress=FALSE)
#' @param rotate if TRUE then the data matrix X is uniformly randomly rotated for each tree. (rotate=FALSE)
#' @param num.cores the number of cores to use while training. If num.cores=0 then 1 less than the number of cores reported by the OS are used. (num.cores=0)
#' @param seed the seed to use for training the forest. (seed=1)
#' @param cat.map.file a file specifying the grouping of one-of-K encoded columns  (see GetCatMap). If NULL, or if an invalid file is specified, then all features in X are treated as numeric.
#'
#' @return forest
#'
#' @author James Browne (jbrowne6@jhu.edu) and Tyler Tomita (ttomita2@jhmi.edu) 
#' 
#' @examples
#' library(rerf)
#' forest <- RerF(as.matrix(iris[, 1:4]), iris[[5L]], num.cores = 1L)
#'
#' @export
#' @importFrom compiler setCompilerOptions cmpfun
#' @importFrom parallel detectCores mclapply mc.reset.stream

RerF <-
    function(X, Y, min.parent = 6L, trees = 100L, 
             max.depth = 0L, bagging = .2, 
             replacement = TRUE, stratify = FALSE, 
             fun = NULL, 
             mat.options = list(p = ncol(X), d = ceiling(sqrt(ncol(X))), random.matrix = "binary", rho = 1/ncol(X)), 
             rank.transform = FALSE, store.oob = FALSE, 
             store.ns = FALSE, progress = FALSE, 
             rotate = F, num.cores = 0L, 
             seed = 1L, cat.map.file = NULL){

        forest <- list(trees = NULL, labels = NULL, params = NULL)

        # check if data matrix X has one-of-K encoded categorical features that need to be handled specially using RandMatCat instead of RandMat
        if (!is.null(cat.map.file)) {
            if (file.exists(cat.map.file)) {
                if (is.null(fun)) {
                    fun <- RandMatCat
                    mat.options[5L] <- GetCatMap(cat.map.file)
                }
            } else {
                if (is.null(fun)) {
                    fun <- RandMat
                }
            }
        } else {
            if (is.null(fun)) {
                fun <- RandMat
            }
        }

        #keep from making copies of X
        if (!is.matrix(X)) {
            X <- as.matrix(X)
        }
        if (rank.transform) {
            X <- RankMatrix(X)
        }

        # adjust Y to go from 1 to num.class if needed
        if (is.factor(Y)) {
            forest$labels <- levels(Y)
            Y <- as.integer(Y)
        } else if (is.numeric(Y)) {
            forest$labels <- sort(unique(Y))
            Y <- as.integer(as.factor(Y))
        } else {
            stop("Incompatible data type. Y must be of type factor or numeric.")
        }
        num.class <- length(forest$labels)
        classCt <- cumsum(tabulate(Y, num.class))
        if(stratify){
            Cindex<-vector("list",num.class)
            for(m in 1L:num.class){
                Cindex[[m]]<-which(Y==m)
            }
        }else{
            Cindex<-NULL
        }

        mcrun<- function(...) BuildTree(X, Y, min.parent, max.depth, bagging, replacement, stratify, Cindex, classCt, fun, mat.options, store.oob=store.oob, store.ns=store.ns, progress=progress, rotate)

        forest$params <- list(min.parent = min.parent, 
                              max.depth = max.depth, 
                              bagging = bagging,
                              replacement = replacement, 
                              stratify = stratify, 
                              fun = fun, 
                              mat.options = mat.options,
                              rank.transform = rank.transform, 
                              store.oob = store.oob, 
                              store.ns = store.ns,
                              rotate = rotate, 
                              seed = seed)

        if (num.cores!=1L){
            RNGkind("L'Ecuyer-CMRG")
            set.seed(seed)
            parallel::mc.reset.stream()
            if(num.cores==0){
                #Use all but 1 core if num.cores=0.
                num.cores=parallel::detectCores()-1L
            }
            num.cores=min(num.cores,trees)
            gc()
            forest$trees <- parallel::mclapply(1:trees, mcrun, mc.cores = num.cores, mc.set.seed=TRUE)
        }else{
            #Use just one core.
            forest$trees <- lapply(1:trees, mcrun)
        }
        return(forest)
    }