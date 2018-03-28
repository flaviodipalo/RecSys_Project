from data.movielens_1m.Movielens1MReader import Movielens1MReader
from SLIM_RMSE.SLIM_RMSE import SLIM_RMSE
from cython.parallel import parallel,  prange
cimport cython
from libc.stdio cimport printf


import numpy as np

from libc.math cimport sqrt
import random
#call(shlex.split('python3 /home/alessio/PycharmProjects/RecSys_Project/our_code/SLIM_RMSE/setup.py build_ext --inplace'))
#python setup.py build_ext --inplace
import time
import timeit
#TODO: portare le funzioni di prodotto fra matrici fuori dalla classe, idealmente in un nuovo file.

#TODO: valutare il codice secondo le metriche sfruttando il codice di MFD.
#TODO: parallelizzare

#TODO: cambiare il gradient e provare con la nostra alternativa

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.initializedcheck(False)
cdef double cython_product_sparse(int[:] URM_indices, double[:] URM_data, double[:] S_column, int column_index_with_zero) nogil:

        cdef double result = 0
        cdef int x

        for x in range(URM_data.shape[0]):
            if URM_indices[x] != column_index_with_zero:
                result += URM_data[x]*S_column[URM_indices[x]]

        return result


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.initializedcheck(False)
cdef double[:] prediction_error(int[:] URM_indptr, int[:] URM_indices, double[:] URM_data, double[:] S, int[:] t_column_indices, double[:] t_column_data, int column_index_with_zero, double[:] prediction) nogil:

        #cdef double[:] prediction = np.zeros(len(t_column_indices))
        cdef int x, user, index, i
        cdef int[:] user_indices
        cdef double[:] user_data

        for index in range(t_column_indices.shape[0]):
            user = t_column_indices[index]
            user_indices = URM_indices[URM_indptr[user]:URM_indptr[user + 1]]
            user_data = URM_data[URM_indptr[user]:URM_indptr[user + 1]]

            prediction[index] = 0
            for x in range(user_data.shape[0]):
                if user_indices[x] != column_index_with_zero:
                    prediction[index] += user_data[x]*S[user_indices[x]]
            prediction[index] = t_column_data[index] - prediction[index]

        return prediction

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.initializedcheck(False)
cdef double cython_norm(double[:] vector, int option) nogil:

    cdef int i
    cdef double counter = 0

    if option == 2:
        for i in range(vector.shape[0]):
            counter += vector[i]**2
        counter = sqrt(counter)
    elif option == 1:
        for i in range(vector.shape[0]):
            counter += vector[i]

    return counter


cdef class CythonEpoch:

    cdef double[:] users
    cdef double[:] movies

    cdef double[:] ratings

    cdef int[:] item_indptr
    cdef int[:] item_indices
    cdef double[:] item_data

    cdef int[:] URM_indptr
    cdef int[:] URM_indices
    cdef double[:] URM_data

    cdef double[:, :] S

    cdef int n_users
    cdef int n_movies

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.initializedcheck(False)
    def __init__(self, URM_train):

        self.n_users = URM_train.shape[0]
        self.n_movies = URM_train.shape[1]
        self.URM_indices = URM_train.indices
        self.URM_data = URM_train.data
        self.URM_indptr = URM_train.indptr

        csc_URM_train = URM_train.tocsc()
        self.item_indptr = csc_URM_train.indptr
        self.item_indices = csc_URM_train.indices
        self.item_data = csc_URM_train.data

    def fit(self,learning_rate,gamma,beta,iterations,threshold):

        cdef int[:] item_indptr
        cdef int[:] item_indices
        cdef double[:] item_data

        cdef int[:] URM_indptr
        cdef int[:] URM_indices
        cdef double[:] URM_data

        cdef int user_index
        cdef int j
        cdef int i
        cdef int index
        cdef int n_iter
        cdef int t_index

        cdef double alpha = learning_rate
        cdef int i_gamma = gamma
        cdef double i_beta = beta
        cdef int i_iterations = iterations
        cdef int i_threshold = threshold
        cdef double eps = 1e-8

        cdef double[:, :] S = np.random.rand(self.n_movies, self.n_movies)
        cdef int[:] URM_without_indptr, t_column_indices
        cdef int[:, :] URM_without_indices, URM_without_data
        cdef double[:] t_column_data
        cdef double [:] prediction = np.zeros(self.n_users)
        cdef double[:, :] G
        cdef double gradient

        cdef double error_function
        cdef double partial_error

        cdef int counter
        cdef int time_counter = 0
        cdef int[:] URM_vector_indices
        cdef double[:] URM_vector_data

        # Needed for Adagrad
        G = np.zeros((self.n_movies, self.n_movies))

        item_indices = self.item_indices
        item_indptr = self.item_indptr
        item_data = self.item_data

        URM_indices = self.URM_indices
        URM_indptr = self.URM_indptr
        URM_data = self.URM_data

        with nogil, parallel():
            for j in prange(1, self.n_movies):
                printf("Column %d\n", j)

                #t_column_indices = item_indices[item_indptr[j]:item_indptr[j+1]]
                #t_column_data = item_data[item_indptr[j]:item_indptr[j+1]]

                for n_iter in range(i_iterations):
                    if n_iter % 100 == 0:
                        printf("Iteration #%d of column #%d\n", n_iter, j)

                    counter = 0
                    for t_index in range(item_indices[item_indptr[j]:item_indptr[j+1]].shape[0]):
                        user_index = item_indices[item_indptr[j]:item_indptr[j+1]][t_index]
                        #URM_vector_indices = URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]]
                        #URM_vector_data = URM_data[URM_indptr[user_index]:URM_indptr[user_index+1]]
                        partial_error = (cython_product_sparse(URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]], URM_data[URM_indptr[user_index]:URM_indptr[user_index+1]], S[:, j], j) - item_data[item_indptr[j]:item_indptr[j+1]][counter])

                        for index in range(URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]].shape[0]):
                            if URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index] != j:
                                gradient = partial_error*URM_data[URM_indptr[user_index]:URM_indptr[user_index+1]][index]+ i_beta*S[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] + i_gamma
                                G[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] += gradient**2
                                S[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] -= (alpha/sqrt(G[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] + eps))*gradient
                            if S[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] < 0:
                                S[URM_indices[URM_indptr[user_index]:URM_indptr[user_index+1]][index], j] = 0
                        counter = counter + 1

                    error_function = cython_norm(prediction_error(URM_indptr, URM_indices, URM_data, S[:, j], item_indices[item_indptr[j]:item_indptr[j+1]], item_data[item_indptr[j]:item_indptr[j+1]], j, prediction), 2)**2 + i_beta*cython_norm(S[:, j], 2)**2  + i_gamma*cython_norm(S[:, j], 1)

          print('training Completed !')
        self.S = S
