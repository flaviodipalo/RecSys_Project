import numpy as np
import scipy.sparse as sps
import os
import random

class Movielens1MReader(object):
    #TODO: aggiungere validation option.
    def __init__(self, train_test_split=None, train_validation_split=None, delete_popular=None, top_popular_threshold=0.33):
        '''
        :param train_test_split: is the percentage of the training set
        '''


        dir = os.path.dirname(__file__)
        filename = dir+"/ratings.dat"

        data = np.loadtxt(filename, delimiter="::")
        #data2 = np.loadtxt(filename2, delimiter="::")

        #These arrays are sorted by user
        self.users = np.array(data[:,0]).astype(int)
        self.movies = np.array(data[:,1]).astype(int)
        self.ratings = np.array(data[:,2])

        if delete_popular:
            unique, counts = np.unique(self.movies, return_counts=True)
            dictionary = dict(zip(unique, counts))
            sorted_dictionary = sorted(dictionary.items(), key=lambda x: x[1])
            cutting_index = round(len(sorted_dictionary)*(1-top_popular_threshold))
            least_popular_item = [x[0] for x in sorted_dictionary[:cutting_index]]

            popular_mask = []
            for item in self.movies:

                if item in least_popular_item:
                    popular_mask.append(True)
                else:
                    popular_mask.append(False)

            self.movies = self.movies[popular_mask]
            self.users = self.users[popular_mask]
            self.ratings = self.ratings[popular_mask]

        self.unique_movies = np.sort(np.unique(self.movies)).astype(int)
        self.unique_users = np.sort(np.unique(self.users))
        '''
        #These arrays are sorted by item
        self.users_by_item = np.array(data2[:,0])
        self.items_by_item = np.array(data2[:,1])
        self.ratings_by_item = np.array(data2[:,2])
   
        # gli id degli users partono da 1 e sono tutti consecutivi, quindi l'unica
        # riga della URM che ha tutti 0 è la prima (riga 0) che quindi eliminiamo
        '''
        URM_all_partial = sps.csr_matrix((self.ratings, (self.users, self.movies)), dtype=np.float32)
        self.URM_all = URM_all_partial
        self.URM_all = self.URM_all.tocoo()

        num_interactions = self.URM_all.nnz

        train_mask = np.random.choice([True, False], num_interactions, p=[train_test_split, 1 - train_test_split])
        test_mask = np.logical_not(train_mask)

        if train_validation_split is not None:

            splitted_test_mask = [random.choice([True, False]) if x else False for x in test_mask]
            validation_mask = np.logical_and(np.logical_not(splitted_test_mask), test_mask)

            self.URM_validation = sps.csr_matrix((self.ratings[validation_mask], (self.users[validation_mask], self.movies[validation_mask])))

        elif train_test_split is not None:
            train_mask = np.random.choice([True, False], num_interactions, p=[train_test_split, 1 - train_test_split])

            test_mask = np.logical_not(train_mask)

        else:
            raise Exception("One between train_test_split and train_validation_split must be valid")

        self.URM_test = sps.csr_matrix((self.ratings[test_mask], (self.users[test_mask], self.movies[test_mask])))

        self.URM_train = sps.csr_matrix((self.ratings[train_mask], (self.users[train_mask], self.movies[train_mask])))

        #print(num_interactions, self.URM_test.nnz, self.URM_train.nnz, self.URM_validation.nnz)

#dataset = Movielens1MReader(0.8,0.9)