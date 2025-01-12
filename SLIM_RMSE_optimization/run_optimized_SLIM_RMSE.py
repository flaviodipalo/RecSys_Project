import sys
sys.path.append('/home/alexbacce/.local/lib/python3.6/site-packages')

from SLIM_RMSE_Cython import SLIM_RMSE_Cython
from data.movielens_1m.Movielens1MReader import Movielens1MReader
from data.book_crossing.BookCrossingReader import BookCrossingReader
from data.movielens_10m.Movielens10MReader import Movielens10MReader
import argparse

from ParameterTuning import BayesianSearch
from ParameterTuning.AbstractClassSearch import DictionaryKeys

#ssh -i /Users/flaviodipalo/Downloads/recsys-project.pem ubuntu@131.175.21.230
parser = argparse.ArgumentParser()
parser.add_argument("normalized", type=str)
parser.add_argument("popular", type=str)

args = parser.parse_args()
normalized = args.normalized
popular = args.popular

if popular == "False":
    popular = False
elif popular == "True":
    popular = True
else:
    raise Exception("Wrong argument")

if normalized == "False":
    normalized = False
elif normalized == "True":
    normalized = True
else:
    raise Exception("Wrong argument")

def run_recommender(normalized, popular):
    #cython epoch only version
    print('Loading Data...')
    #data_reader = Movielens1MReader(train_test_split=0.8)
    data_reader = Movielens10MReader(train_test_split=0.8, delete_popular=popular, k_cores=50)
    #data_reader = BookCrossingReader(train_test_split=0.8)
    URM_train = data_reader.URM_train
    URM_test = data_reader.URM_test
    #URM_validation = data_reader.URM_validation

    print('Data Loaded !')
    recommender = SLIM_RMSE_Cython(URM_train=URM_train, URM_validation=URM_test)

    recommender.fit(epochs=5, similarity_matrix_normalized=normalized)

def run_recommender_optimization(normalized=False, popular=False):
    print('Loading Data...')
    data_reader = Movielens10MReader(train_validation_split=[0.6, 0.2, 0.2], delete_popular=popular, delete_interactions=0.33)
    #data_reader = Movielens1MReader(train_test_split=0.6, train_validation_split=True, delete_popular=popular)
    #data_reader = Movielens1MReader(train_test_split=0.8, delete_popular=popular)
    #data_reader = Movielens10MReader(train_validation_split=[0.8, 0.1, 0.1], delete_popular=popular)
    #data_reader = BookCrossingReader(train_test_split=0.8)
    URM_train = data_reader.URM_train
    URM_test = data_reader.URM_test
    #TODO:pay attention here
    URM_validation = data_reader.URM_test

    print('Data Loaded !')
    #the file path that will print the solution for each configuration file
    file_path = 'Norm_='+str(normalized)+'_delete_popular='+str(popular)
#
    recommender_class = SLIM_RMSE_Cython
    parameterSearch = BayesianSearch.BayesianSearch(recommender_class, URM_validation)

    hyperparamethers_range_dictionary = {}
    hyperparamethers_range_dictionary["topK"] = [100]
    hyperparamethers_range_dictionary["l1_penalty"] = [1e-1, 1e-2]
    hyperparamethers_range_dictionary["l2_penalty"] = [1e-1, 1e-2]

    hyperparamethers_range_dictionary["similarity_matrix_normalized"] = [normalized]
    ##TODO: ci sta che sia un problema dei parametri passati in ingresso al recommender costruito con cattiveria
    recommenderDictionary = {DictionaryKeys.CONSTRUCTOR_POSITIONAL_ARGS: [URM_train,URM_validation],
                              DictionaryKeys.CONSTRUCTOR_KEYWORD_ARGS: {},
                              DictionaryKeys.FIT_POSITIONAL_ARGS: dict(),
                              DictionaryKeys.FIT_KEYWORD_ARGS: dict(),
                              DictionaryKeys.FIT_RANGE_KEYWORD_ARGS: hyperparamethers_range_dictionary}

    parameterSearch.search(recommenderDictionary, output_root_path='logs/new'+file_path)
    parameterSearch.evaluate_on_test(URM_test)

#run_recommender_optimization(normalized, popular)
run_recommender(normalized,popular)
