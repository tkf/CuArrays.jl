using LinearAlgebra

@testset "CUBLAS" begin

using CuArrays.CUBLAS
using CuArrays.CUBLAS: band, bandex

m = 20
n = 35
k = 13

@test_throws ArgumentError CUBLAS.cublasop('V')
@test_throws ArgumentError CUBLAS.cublasfill('V')
@test_throws ArgumentError CUBLAS.cublasdiag('V')
@test_throws ArgumentError CUBLAS.cublasside('V')

# this is an internal function, but only used on some devices so make sure it works
CUBLAS.cublasSetMathMode(CUBLAS.CUBLAS_DEFAULT_MATH)

#################
# level 1 tests #
#################

@testset "Level 1 with element type $T" for T in [Float32, Float64, ComplexF32, ComplexF64]
    A = CuArrays.rand(T, m)
    B = CuArray{T}(undef, m)
    CuArrays.CUBLAS.blascopy!(m,A,1,B,1)
    @test Array(A) == Array(B)

    @test testf(rmul!, rand(T, 6, 9, 3), Ref(rand()))
    @test testf(dot, rand(T, m), rand(T, m))
    @test testf(*, transpose(rand(T, m)), rand(T, m))
    @test testf(*, rand(T, m)', rand(T, m))
    @test testf(norm, rand(T, m))
    @test testf(BLAS.asum, rand(T, m))
    @test testf(BLAS.axpy!, Ref(rand()), rand(T, m), rand(T, m))

    if T <: Real
        @test testf(argmin, rand(T, m))
        @test testf(argmax, rand(T, m))
    else
        @test testf(BLAS.dotu, rand(T, m), rand(T, m))
        x = rand(T, m)
        y = rand(T, m)
        dx = CuArray(x)
        dy = CuArray(y)
        dz = BLAS.dot(dx, dy)
        z = BLAS.dotc(x, y)
        @test dz ≈ z
    end
end # level 1 testset

@testset "element type $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64]
    alpha = convert(elty,2)
    beta = convert(elty,3)

    @testset "Level 2" begin
        @testset "gemv" begin 
            @test testf(*, rand(elty, m, n), rand(elty, n))
            @test testf(*, transpose(rand(elty, m, n)), rand(elty, m))
            @test testf(*, rand(elty, m, n)', rand(elty, m))
            x = rand(elty, m)
            A = rand(elty, m, m + 1 )
            y = rand(elty, m)
            dx = CuArray(x)
            dA = CuArray(A)
            dy = CuArray(y)
            @test_throws DimensionMismatch mul!(dy, dA, dx)
            A = rand(elty, m + 1, m )
            dA = CuArray(A)
            @test_throws DimensionMismatch mul!(dy, dA, dx)
        end
        @testset "banded methods" begin
            # bands
            ku = 2
            kl = 3
            # generate banded matrix
            A = rand(elty,m,n)
            A = bandex(A,kl,ku)
            # get packed format
            Ab = band(A,kl,ku)
            d_Ab = CuArray(Ab)
            x = rand(elty,n)
            d_x = CuArray(x)
            @testset "gbmv!" begin
                # test y = alpha*A*x + beta*y
                y = rand(elty,m)
                d_y = CuArray(y)
                CuArrays.CUBLAS.gbmv!('N',m,kl,ku,alpha,d_Ab,d_x,beta,d_y)
                BLAS.gbmv!('N',m,kl,ku,alpha,Ab,x,beta,y)
                h_y = Array(d_y)
                @test y ≈ h_y
                # test y = alpha*transpose(A)*x + beta*y
                x = rand(elty,n)
                d_x = CuArray(x)
                y = rand(elty,m)
                d_y = CuArray(y)
                CuArrays.CUBLAS.gbmv!('T',m,kl,ku,alpha,d_Ab,d_y,beta,d_x)
                BLAS.gbmv!('T',m,kl,ku,alpha,Ab,y,beta,x)
                h_x = Array(d_x)
                @test x ≈ h_x
                # test y = alpha*A'*x + beta*y
                x = rand(elty,n)
                d_x = CuArray(x)
                y = rand(elty,m)
                d_y = CuArray(y)
                CuArrays.CUBLAS.gbmv!('C',m,kl,ku,alpha,d_Ab,d_y,beta,d_x)
                BLAS.gbmv!('C',m,kl,ku,alpha,Ab,y,beta,x)
                h_x = Array(d_x)
                @test x ≈ h_x
            end
            x = rand(elty,n)
            d_x = CuArray(x)
            @testset "gbmv" begin
                # test y = alpha*A*x
                d_y = CuArrays.CUBLAS.gbmv('N',m,kl,ku,alpha,d_Ab,d_x)
                y = zeros(elty,m)
                y = BLAS.gbmv('N',m,kl,ku,alpha,Ab,x)
                h_y = Array(d_y)
                @test y ≈ h_y
            end
            A = rand(elty,m,m)
            A = A + A'
            nbands = 3
            @test m >= 1+nbands
            A = bandex(A,nbands,nbands)
            # convert to 'upper' banded storage format
            AB = band(A,0,nbands)
            # construct x
            x = rand(elty,m)
            d_AB = CuArray(AB)
            d_x = CuArray(x)
            if elty <: Real
                @testset "sbmv!" begin
                    y = rand(elty,m)
                    d_y = CuArray(y)
                    # sbmv!
                    CuArrays.CUBLAS.sbmv!('U',nbands,alpha,d_AB,d_x,beta,d_y)
                    y = alpha*(A*x) + beta*y
                    # compare
                    h_y = Array(d_y)
                    @test y ≈ h_y
                end
                @testset "sbmv" begin 
                    d_y = CuArrays.CUBLAS.sbmv('U',nbands,d_AB,d_x)
                    y = A*x
                    # compare
                    h_y = Array(d_y)
                    @test y ≈ h_y
                end
            else
                @testset "hbmv!" begin
                    y = rand(elty,m)
                    d_y = CuArray(y)
                    # hbmv!
                    CuArrays.CUBLAS.hbmv!('U',nbands,alpha,d_AB,d_x,beta,d_y)
                    y = alpha*(A*x) + beta*y
                    # compare
                    h_y = Array(d_y)
                    @test y ≈ h_y
                end
                @testset "hbmv" begin
                    d_y = CuArrays.CUBLAS.hbmv('U',nbands,d_AB,d_x)
                    y = A*x
                    # compare
                    h_y = Array(d_y)
                    @test y ≈ h_y
                end
            end
            # generate triangular matrix
            A = rand(elty,m,m)
            # restrict to 3 bands
            nbands = 3
            @test m >= 1+nbands
            A = bandex(A,0,nbands)
            # convert to 'upper' banded storage format
            AB = band(A,0,nbands)
            d_AB = CuArray(AB)
            @testset "tbmv!" begin
                y = rand(elty, m) 
                # move to host
                d_y = CuArray(y)
                # tbmv!
                CuArrays.CUBLAS.tbmv!('U','N','N',nbands,d_AB,d_y)
                y = A*y
                # compare
                h_y = Array(d_y)
                @test y ≈ h_y
            end
            @testset "tbmv" begin
                # tbmv
                d_y = CuArrays.CUBLAS.tbmv('U','N','N',nbands,d_AB,d_x)
                y = A*x
                # compare
                h_y = Array(d_y)
                @test y ≈ h_y
            end
            @testset "tbsv!" begin
                d_y = copy(d_x)
                #tbsv!
                CuArrays.CUBLAS.tbsv!('U','N','N',nbands,d_AB,d_y)
                y = A\x
                # compare
                h_y = Array(d_y)
                @test y ≈ h_y
            end
            @testset "tbsv" begin
                d_y = CuArrays.CUBLAS.tbsv('U','N','N',nbands,d_AB,d_x)
                y = A\x
                # compare
                h_y = Array(d_y)
                @test y ≈ h_y
            end
        end
        A = rand(elty,m,n)
        dA = CuArray(A)
        sA = rand(elty,m,m)
        sA = sA + transpose(sA)
        dsA = CuArray(sA)
        hA = rand(elty,m,m)
        hA = hA + hA'
        dhA = CuArray(hA)
        x = rand(elty,m)
        dx = CuArray(x) 
        @testset "symv!" begin
            # generate vectors
            y = rand(elty,m)
            # copy to device
            dy = CuArray(y)
            # execute on host
            BLAS.symv!('U',alpha,sA,x,beta,y)
            # execute on device
            CuArrays.CUBLAS.symv!('U',alpha,dsA,dx,beta,dy)
            # compare results
            hy = Array(dy)
            @test y ≈ hy
        end

        @testset "symv" begin
            y = BLAS.symv('U',sA,x)
            # execute on device
            dy = CuArrays.CUBLAS.symv('U',dsA,dx)
            # compare results
            hy = Array(dy)
            @test y ≈ hy
        end
        if elty <: Complex
            @testset "hemv!" begin
                y = rand(elty,m)
                dy = CuArray(y)
                # execute on host
                BLAS.hemv!('U',alpha,hA,x,beta,y)
                # execute on device
                CuArrays.CUBLAS.hemv!('U',alpha,dhA,dx,beta,dy)
                # compare results
                hy = Array(dy)
                @test y ≈ hy
            end
            @testset "hemv" begin 
                y = BLAS.hemv('U',hA,x)
                # execute on device
                dy = CuArrays.CUBLAS.hemv('U',dhA,dx)
                # compare results
                hy = Array(dy)
                @test y ≈ hy
            end
        end
        A = triu(sA)
        dA = CuArray(A)
        @testset "trmv!" begin
            d_y = copy(dx)
            # execute trmv!
            CuArrays.CUBLAS.trmv!('U','N','N',dA,d_y)
            y = A*x
            # compare
            h_y = Array(d_y)
            @test y ≈ h_y
        end

        @testset "trmv" begin 
            d_y = CuArrays.CUBLAS.trmv('U','N','N',dA,dx)
            y = A*x
            # compare
            h_y = Array(d_y)
            @test y ≈ h_y
        end

        @testset "trsv!" begin
            d_y = copy(dx)
            # execute trsv!
            CuArrays.CUBLAS.trsv!('U','N','N',dA,d_y)
            y = A\x
            # compare
            h_y = Array(d_y)
            @test y ≈ h_y
        end

        @testset "trsv" begin
            d_y = CuArrays.CUBLAS.trsv('U','N','N',dA,dx)
            y = A\x
            # compare
            h_y = Array(d_y)
            @test y ≈ h_y
        end

        @testset "ldiv!(::UpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(UpperTriangular(dA), dy)
            y = UpperTriangular(A) \ x
            @test y ≈ Array(dy)
        end
        @testset "ldiv!(::AdjointUpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(adjoint(UpperTriangular(dA)), dy)
            y = adjoint(UpperTriangular(A)) \ x
            @test y ≈ Array(dy)
        end
        @testset "ldiv!(::TransposeUpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(transpose(UpperTriangular(dA)), dy)
            y = transpose(UpperTriangular(A)) \ x
            @test y ≈ Array(dy)
        end
        @testset "ldiv!(::UpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(LowerTriangular(dA), dy)
            y = LowerTriangular(A) \ x
            @test y ≈ Array(dy)
        end
        @testset "ldiv!(::AdjointUpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(adjoint(LowerTriangular(dA)), dy)
            y = adjoint(LowerTriangular(A)) \ x
            @test y ≈ Array(dy)
        end
        @testset "ldiv!(::TransposeUpperTriangular, ::CuVector)" begin
            A = copy(sA)
            dA = CuArray(A)
            dy = copy(dx)
            ldiv!(transpose(LowerTriangular(dA)), dy)
            y = transpose(LowerTriangular(A)) \ x
            @test y ≈ Array(dy)
        end

        A = rand(elty,m,m)
        x = rand(elty,m)
        y = rand(elty,m)
        dA = CuArray(A)
        dx = CuArray(x)
        dy = CuArray(y)
        @testset "ger!" begin
            # perform rank one update
            dB = copy(dA)
            CuArrays.CUBLAS.ger!(alpha,dx,dy,dB)
            B = (alpha*x)*y' + A
            # move to host and compare
            hB = Array(dB)
            @test B ≈ hB
        end

        @testset "syr!" begin
            dB = copy(dsA)
            CuArrays.CUBLAS.syr!('U',alpha,dx,dB)
            B = (alpha*x)*transpose(x) + sA
            # move to host and compare upper triangles
            hB = Array(dB)
            B = triu(B)
            hB = triu(hB)
            @test B ≈ hB
        end
        if elty <: Complex
            @testset "her!" begin
                dB = copy(dhA) 
                # perform rank one update
                CuArrays.CUBLAS.her!('U',alpha,dx,dB)
                B = (alpha*x)*x' + hA
                # move to host and compare upper triangles
                hB = Array(dB)
                B = triu(B)
                hB = triu(hB)
                @test B ≈ hB
            end

            @testset "her2!" begin
                dB = copy(dhA) 
                CuArrays.CUBLAS.her2!('U',alpha,dx,dy,dB)
                B = (alpha*x)*y' + y*(alpha*x)' + hA
                # move to host and compare upper triangles
                hB = Array(dB)
                B = triu(B)
                hB = triu(hB)
                @test B ≈ hB
            end
        end
    end
    @testset "Level 3" begin
        A = rand(elty,m,k)
        B = rand(elty,k,n)
        C1 = rand(elty,m,n)
        C2 = copy(C1)
        d_A = CuArray(A)
        d_B = CuArray(B)
        d_C1 = CuArray(C1)
        d_C2 = CuArray(C2)
        hA = rand(elty,m,m)
        hA = hA + hA'
        dhA = CuArray(hA)
        sA = rand(elty,m,m)
        sA = sA + transpose(sA)
        dsA = CuArray(sA)
        @testset "gemm!" begin
            CuArrays.CUBLAS.gemm!('N','N',alpha,d_A,d_B,beta,d_C1)
            mul!(d_C2, d_A, d_B)
            h_C1 = Array(d_C1)
            h_C2 = Array(d_C2)
            C1 = (alpha*A)*B + beta*C1
            C2 = A*B
            # compare
            @test C1 ≈ h_C1
            @test C2 ≈ h_C2
            @test_throws ArgumentError mul!(dhA, dhA, dsA)
            @test_throws DimensionMismatch mul!(d_C1, d_A, dsA)
        end

        @testset "gemm" begin
            d_C = CuArrays.CUBLAS.gemm('N','N',d_A,d_B)
            C = A*B
            C2 = d_A * d_B
            # compare
            h_C = Array(d_C)
            h_C2 = Array(C2)
            @test C ≈ h_C
            @test C ≈ h_C2
        end
        @testset "xt_gemm!" begin
            CuArrays.CUBLAS.xt_gemm!('N','N',alpha,d_A,d_B,beta,d_C1)
            mul!(d_C2, d_A, d_B)
            h_C1 = Array(d_C1)
            h_C2 = Array(d_C2)
            C1 = (alpha*A)*B + beta*C1
            C2 = A*B
            # compare
            @test C1 ≈ h_C1
            @test C2 ≈ h_C2
        end

        @testset "xt_gemm" begin
            d_C = CuArrays.CUBLAS.xt_gemm('N','N',d_A,d_B)
            C = A*B
            C2 = d_A * d_B
            # compare
            h_C = Array(d_C)
            h_C2 = Array(C2)
            @test C ≈ h_C
            @test C ≈ h_C2
        end
        # generate matrices
        bA = [rand(elty,m,k) for i in 1:10]
        bB = [rand(elty,k,n) for i in 1:10]
        bC = [rand(elty,m,n) for i in 1:10]
        # move to device
        bd_A = CuArray{elty, 2}[]
        bd_B = CuArray{elty, 2}[]
        bd_C = CuArray{elty, 2}[]
        for i in 1:length(bA)
            push!(bd_A,CuArray(bA[i]))
            push!(bd_B,CuArray(bB[i]))
            push!(bd_C,CuArray(bC[i]))
        end
        @testset "gemm_batched!" begin
            # C = (alpha*A)*B + beta*C
            CuArrays.CUBLAS.gemm_batched!('N','N',alpha,bd_A,bd_B,beta,bd_C)
            for i in 1:length(bd_C)
                bC[i] = (alpha*bA[i])*bB[i] + beta*bC[i]
                h_C = Array(bd_C[i])
                #compare
                @test bC[i] ≈ h_C
            end
        end

        @testset "gemm_batched" begin 
            bd_C = CuArrays.CUBLAS.gemm_batched('N','N',bd_A,bd_B)
            for i in 1:length(bA)
                bC = bA[i]*bB[i]
                h_C = Array(bd_C[i])
                @test bC ≈ h_C
            end
        end

        nbatch = 10
        bA = rand(elty, m, k, nbatch)
        bB = rand(elty, k, n, nbatch)
        bC = rand(elty, m, n, nbatch)
        # move to device
        bd_A = CuArray{elty, 3}(bA)
        bd_B = CuArray{elty, 3}(bB)
        bd_C = CuArray{elty, 3}(bC)
        @testset "gemm_strided_batched!" begin
            CuArrays.CUBLAS.gemm_strided_batched!('N', 'N', alpha, bd_A, bd_B, beta, bd_C)
            for i in 1:nbatch
                bC[:, :, i] = (alpha * bA[:, :, i]) * bB[:, :, i] + beta * bC[:, :, i]
            end
            h_C = Array(bd_C)
            @test bC ≈ h_C
        end

        @testset "gemm_strided_batched" begin 
            bd_C = CuArrays.CUBLAS.gemm_strided_batched('N', 'N', bd_A, bd_B)

            for i in 1:nbatch
                bC[:, :, i] = bA[:, :, i] * bB[:, :, i]
            end
            h_C = Array(bd_C)
            @test bC ≈ h_C
            # generate matrices
            bA = rand(elty, k, m, nbatch)
            bB = rand(elty, k, n, nbatch)
            bC = zeros(elty, m, n, nbatch)
            # move to device
            bd_A = CuArray{elty, 3}(bA)
            bd_B = CuArray{elty, 3}(bB)

            bd_C = CuArrays.CUBLAS.gemm_strided_batched('T', 'N', bd_A, bd_B)
            for i in 1:nbatch
                bC[:, :, i] = transpose(bA[:, :, i]) * bB[:, :, i]
            end
            h_C = Array(bd_C)
            @test bC ≈ h_C
        end

        B = rand(elty,m,n)
        C = rand(elty,m,n)
        d_B = CuArray(B)
        d_C = CuArray(C)
        @testset "symm!" begin
            CuArrays.CUBLAS.symm!('L','U',alpha,dsA,d_B,beta,d_C)
            C = (alpha*sA)*B + beta*C
            # compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end

        @testset "symm" begin
            d_C = CuArrays.CUBLAS.symm('L','U',dsA,d_B)
            C = sA*B
            # compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end
        @testset "xt_symm!" begin
            CuArrays.CUBLAS.xt_symm!('L','U',alpha,dsA,d_B,beta,d_C)
            C = (alpha*sA)*B + beta*C
            # compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end

        @testset "xt_symm" begin
            d_C = CuArrays.CUBLAS.xt_symm('L','U',dsA,d_B)
            C = sA*B
            # compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end
        A = triu(rand(elty, m, m))
        B = rand(elty,m,n)
        C = zeros(elty,m,n)
        dA = CuArray(A)
        dB = CuArray(B)
        dC = CuArray(C)
        @testset "trmm!" begin
            C = alpha*A*B
            CuArrays.CUBLAS.trmm!('L','U','N','N',alpha,dA,dB,dC)
            # move to host and compare
            h_C = Array(dC)
            @test C ≈ h_C
        end
        @testset "trmm" begin
            C = alpha*A*B
            d_C = CuArrays.CUBLAS.trmm('L','U','N','N',alpha,dA,dB)
            # move to host and compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end
        @testset "xt_trmm!" begin
            C = alpha*A*B
            CuArrays.CUBLAS.xt_trmm!('L','U','N','N',alpha,dA,dB,dC)
            # move to host and compare
            h_C = Array(dC)
            @test C ≈ h_C
        end
        @testset "xt_trmm" begin
            C = alpha*A*B
            d_C = CuArrays.CUBLAS.xt_trmm('L','U','N','N',alpha,dA,dB)
            # move to host and compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end
        @testset "trsm!" begin
            C = alpha*(A\B)
            dC = copy(dB)
            CuArrays.CUBLAS.trsm!('L','U','N','N',alpha,dA,dC)
            # move to host and compare
            h_C = Array(dC)
            @test C ≈ h_C
        end
        @testset "xt_trsm!" begin
            C = alpha*(A\B)
            dC = copy(dB)
            CuArrays.CUBLAS.xt_trsm!('L','U','N','N',alpha,dA,dC)
            # move to host and compare
            h_C = Array(dC)
            @test C ≈ h_C
        end
        @testset "trsm" begin
            Br = rand(elty,m,n)
            Bl = rand(elty,n,m)
            d_Br = CuArray(Br)
            d_Bl = CuArray(Bl)
            # compute
            @testset "adjtype=$adjtype, uplotype=$uplotype" for
                adjtype in (identity, adjoint, transpose),
                    uplotype in (UpperTriangular, UnitUpperTriangular, LowerTriangular, UnitLowerTriangular)

                @test adjtype(uplotype(A))\Br ≈ Array(adjtype(uplotype(dA))\d_Br)
                @test Bl/adjtype(uplotype(A)) ≈ Array(d_Bl/adjtype(uplotype(dA)))
            end
            # Check also that scaling parameter works
            @test BLAS.trsm('L','U','N','N',alpha,A,Br) ≈ Array(CuArrays.CUBLAS.trsm('L','U','N','N',alpha,dA,d_Br))
        end

        @testset "trsm_batched!" begin
            bA = [rand(elty,m,m) for i in 1:10]
            map!((x) -> triu(x), bA, bA)
            bB = [rand(elty,m,n) for i in 1:10]
            # move to device
            bd_A = CuArray{elty, 2}[]
            bd_B = CuArray{elty, 2}[]
            for i in 1:length(bA)
                push!(bd_A,CuArray(bA[i]))
                push!(bd_B,CuArray(bB[i]))
            end
            # compute
            CuArrays.CUBLAS.trsm_batched!('L','U','N','N',alpha,bd_A,bd_B)
            # move to host and compare
            for i in 1:length(bd_B)
                bC = alpha*(bA[i]\bB[i])
                h_C = Array(bd_B[i])
                #compare
                @test bC ≈ h_C
            end
        end

        @testset "trsm_batched" begin
            # generate parameter alpha = rand(elty)
            # generate matrices
            bA = [rand(elty,m,m) for i in 1:10]
            map!((x) -> triu(x), bA, bA)
            bB = [rand(elty,m,n) for i in 1:10]
            # move to device
            bd_A = CuArray{elty, 2}[]
            bd_B = CuArray{elty, 2}[]
            for i in 1:length(bA)
                push!(bd_A,CuArray(bA[i]))
                push!(bd_B,CuArray(bB[i]))
            end
            # compute
            bd_C = CuArrays.CUBLAS.trsm_batched('L','U','N','N',alpha,bd_A,bd_B)
            # move to host and compare
            for i in 1:length(bd_C)
                bC = alpha*(bA[i]\bB[i])
                h_C = Array(bd_C[i])
                @test bC ≈ h_C
            end
        end
        B = rand(elty,m,n)
        C = rand(elty,m,n)
        d_B = CuArray(B)
        d_C = CuArray(C)
        if elty <: Complex
            @testset "hemm!" begin
                # compute
                C = alpha*(hA*B) + beta*C
                CuArrays.CUBLAS.hemm!('L','L',alpha,dhA,d_B,beta,d_C)
                # move to host and compare
                h_C = Array(d_C)
                @test C ≈ h_C
            end
            @testset "hemm" begin
                C = alpha*(hA*B)
                d_C = CuArrays.CUBLAS.hemm('L','U',alpha,dhA,d_B)
                # move to host and compare
                h_C = Array(d_C)
                @test C ≈ h_C
            end
            @testset "xt_hemm!" begin
                # compute
                C = alpha*(hA*B) + beta*C
                CuArrays.CUBLAS.xt_hemm!('L','L',alpha,dhA,d_B,beta,d_C)
                # move to host and compare
                h_C = Array(d_C)
                @test C ≈ h_C
            end
            @testset "xt_hemm" begin
                C = alpha*(hA*B)
                d_C = CuArrays.CUBLAS.xt_hemm('L','U',alpha,dhA,d_B)
                # move to host and compare
                h_C = Array(d_C)
                @test C ≈ h_C
            end
        end
        A = rand(elty,m,n)
        d_A = CuArray(A)
        @testset "geam!" begin
            # compute
            D = alpha*A + beta*B
            CuArrays.CUBLAS.geam!('N','N',alpha,d_A,beta,d_B,d_C)
            # move to host and compare
            h_C = Array(d_C)
            @test D ≈ h_C

            #test in place versions too
            d_C = CuArray(C)
            D = alpha*C + beta*B
            CuArrays.CUBLAS.geam!('N','N',alpha,d_C,beta,d_B,d_C)
            # move to host and compare
            h_C = Array(d_C)
            @test D ≈ h_C

            d_C = CuArray(C)
            D = alpha*A + beta*C
            CuArrays.CUBLAS.geam!('N','N',alpha,d_A,beta,d_C,d_C)
            # move to host and compare
            h_C = Array(d_C)
            @test D ≈ h_C

            #test setting C to zero
            CuArrays.CUBLAS.geam!('N','N',zero(elty),d_A,zero(elty),d_B,d_C)
            h_C = Array(d_C)
            @test h_C ≈ zeros(elty,m,n)

            # bounds checking
            @test_throws DimensionMismatch CuArrays.CUBLAS.geam!('N','T',alpha,d_A,beta,d_B,d_C)
            @test_throws DimensionMismatch CuArrays.CUBLAS.geam!('T','T',alpha,d_A,beta,d_B,d_C)
            @test_throws DimensionMismatch CuArrays.CUBLAS.geam!('T','N',alpha,d_A,beta,d_B,d_C)
        end

        @testset "geam" begin
            D = alpha*A + beta*B
            d_C = CuArrays.CUBLAS.geam('N','N',alpha,d_A,beta,d_B)
            # move to host and compare
            h_C = Array(d_C)
            @test D ≈ h_C
        end
        A = rand(elty,m,k)
        d_A = CuArray(A)
        @testset "syrk!" begin
            # generate matrices
            d_C = CuArray(sA)
            # C = (alpha*A)*transpose(A) + beta*C
            CuArrays.CUBLAS.syrk!('U','N',alpha,d_A,beta,d_C)
            C = (alpha*A)*transpose(A) + beta*sA
            C = triu(C)
            # move to host and compare
            h_C = Array(d_C)
            h_C = triu(C)
            @test C ≈ h_C
        end
        @testset "xt_syrk!" begin
            # generate matrices
            d_C = CuArray(sA)
            # C = (alpha*A)*transpose(A) + beta*C
            CuArrays.CUBLAS.xt_syrk!('U','N',alpha,d_A,beta,d_C)
            C = (alpha*A)*transpose(A) + beta*sA
            C = triu(C)
            # move to host and compare
            h_C = Array(d_C)
            h_C = triu(C)
            @test C ≈ h_C
        end
        @testset "syrk" begin
            # C = A*transpose(A)
            d_C = CuArrays.CUBLAS.syrk('U','N',d_A)
            C = A*transpose(A)
            C = triu(C)
            # move to host and compare
            h_C = Array(d_C)
            h_C = triu(C)
            @test C ≈ h_C
        end
        @testset "xt_syrk" begin
            # C = A*transpose(A)
            d_C = CuArrays.CUBLAS.xt_syrk('U','N',d_A)
            C = A*transpose(A)
            C = triu(C)
            # move to host and compare
            h_C = Array(d_C)
            h_C = triu(C)
            @test C ≈ h_C
        end
        if elty <: Complex
            @testset "herk!" begin 
                d_C = CuArray(dhA)
                CuArrays.CUBLAS.herk!('U','N',alpha,d_A,beta,d_C)
                C = alpha*(A*A') + beta*C
                C = triu(C)
                # move to host and compare
                h_C = Array(d_C)
                h_C = triu(C)
                @test C ≈ h_C
            end
            @testset "herk" begin
                d_C = CuArrays.CUBLAS.herk('U','N',d_A)
                C = A*A'
                C = triu(C)
                # move to host and compare
                h_C = Array(d_C)
                h_C = triu(C)
                @test C ≈ h_C
            end
            @testset "xt_herk!" begin 
                d_C = CuArray(dhA)
                CuArrays.CUBLAS.xt_herk!('U','N',alpha,d_A,beta,d_C)
                C = alpha*(A*A') + beta*C
                C = triu(C)
                # move to host and compare
                h_C = Array(d_C)
                h_C = triu(C)
                @test C ≈ h_C
            end
            @testset "xt_herk" begin
                d_C = CuArrays.CUBLAS.xt_herk('U','N',d_A)
                C = A*A'
                C = triu(C)
                # move to host and compare
                h_C = Array(d_C)
                h_C = triu(C)
                @test C ≈ h_C
            end
        end
        A = rand(elty,m,k)
        B = rand(elty,m,k)
        C = rand(elty,m,m)
        C = C + transpose(C)
        # move to device
        d_A = CuArray(A)
        d_B = CuArray(B)
        d_C = CuArray(C)
        @testset "syr2k!" begin
            # compute
            C = alpha*(A*transpose(B) + B*transpose(A)) + beta*C
            CuArrays.CUBLAS.syr2k!('U','N',alpha,d_A,d_B,beta,d_C)
            # move back to host and compare
            C = triu(C)
            h_C = Array(d_C)
            h_C = triu(h_C)
            @test C ≈ h_C
        end

        @testset "syr2k" begin
            C = alpha*(A*transpose(B) + B*transpose(A))
            d_C = CuArrays.CUBLAS.syr2k('U','N',alpha,d_A,d_B)
            # move back to host and compare
            C = triu(C)
            h_C = Array(d_C)
            h_C = triu(h_C)
            @test C ≈ h_C
        end
        if elty <: Complex
            @testset "her2k!" begin
                elty1 = elty
                elty2 = real(elty)
                # generate parameters
                α = rand(elty1)
                β = rand(elty2)
                C = C + C'
                d_C = CuArray(C)
                C = α*(A*B') + conj(α)*(B*A') + β*C
                CuArrays.CUBLAS.her2k!('U','N',α,d_A,d_B,β,d_C)
                # move back to host and compare
                C = triu(C)
                h_C = Array(d_C)
                h_C = triu(h_C)
                @test C ≈ h_C
            end

            @testset "her2k" begin
                C = A*B' + B*A'
                d_C = CuArrays.CUBLAS.her2k('U','N',d_A,d_B)
                # move back to host and compare
                C = triu(C)
                h_C = Array(d_C)
                h_C = triu(h_C)
                @test C ≈ h_C
            end
            @testset "xt_her2k!" begin
                elty1 = elty
                elty2 = real(elty)
                # generate parameters
                α = rand(elty1)
                β = rand(elty2)
                C = C + C'
                d_C = CuArray(C)
                C = α*(A*B') + conj(α)*(B*A') + β*C
                CuArrays.CUBLAS.xt_her2k!('U','N',α,d_A,d_B,β,d_C)
                # move back to host and compare
                C = triu(C)
                h_C = Array(d_C)
                h_C = triu(h_C)
                @test C ≈ h_C
            end
            @testset "her2k" begin
                C = A*B' + B*A'
                d_C = CuArrays.CUBLAS.her2k('U','N',d_A,d_B)
                # move back to host and compare
                C = triu(C)
                h_C = Array(d_C)
                h_C = triu(h_C)
                @test C ≈ h_C
            end
        end
    end
    @testset "extensions" begin
        @testset "getrf_batched!" begin
            Random.seed!(1)
            local k
            # generate matrices
            A = [rand(elty,m,m) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            pivot, info = CuArrays.CUBLAS.getrf_batched!(d_A, false)
            h_info = Array(info)
            for As in 1:length(d_A)
                C   = lu!(copy(A[As]), Val(false)) # lu(A[As],pivot=false)
                h_A = Array(d_A[As])
                #reconstruct L,U
                dL = Matrix(one(elty)*I, m, m)
                dU = zeros(elty,(m,m))
                k = h_info[As]
                if( k >= 0 )
                    dL += tril(h_A,-k-1)
                    dU += triu(h_A,k)
                end
                #compare
                @test C.L ≈ dL rtol=1e-2
                @test C.U ≈ dU rtol=1e-2
            end
            for i in 1:length(A)
                d_A[ i ] = CuArray(A[i])
            end
            pivot, info = CuArrays.CUBLAS.getrf_batched!(d_A, true)
            h_info = Array(info)
            h_pivot = Array(pivot)
            for As in 1:length(d_A)
                C   = lu(A[As])
                h_A = Array(d_A[As])
                #reconstruct L,U
                dL = Matrix(one(elty)*I, m, m)
                dU = zeros(elty,(m,m))
                k = h_info[As]
                if( k >= 0 )
                    dL += tril(h_A,-k-1)
                    dU += triu(h_A,k)
                end
                #compare pivots
                @test length(setdiff(h_pivot[:,As],C.p)) == 0
                #make device pivot matrix
                P = Matrix(1.0*I, m, m)
                for row in 1:m
                    temp = copy(P[row,:])
                    P[row,:] = P[h_pivot[row,As],:]
                    P[h_pivot[row,As],:] = temp
                end
                @test inv(P)*dL*dU ≈ inv(C.P) * C.L * C.U
            end
        end

        @testset "getrf_batched" begin
            local k
            # generate matrices
            A = [rand(elty,m,m) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            pivot, info, d_B = CuArrays.CUBLAS.getrf_batched(d_A, false)
            h_info = Array(info)
            for Bs in 1:length(d_B)
                C   = lu!(copy(A[Bs]),Val(false)) # lu(A[Bs],pivot=false)
                h_B = Array(d_B[Bs])
                #reconstruct L,U
                dL = Matrix(one(elty)*I, m, m)
                dU = zeros(elty,(m,m))
                k = h_info[Bs]
                if( h_info[Bs] >= 0 )
                    dU += triu(h_B,k)
                    dL += tril(h_B,-k-1)
                end
                #compare
                @test C.L ≈ dL rtol=1e-2
                @test C.U ≈ dU rtol=1e-2
            end
        end

        @testset "getri_batched" begin
            # generate matrices
            A = [rand(elty,m,m) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            pivot, info = CuArrays.CUBLAS.getrf_batched!(d_A, true)
            h_info = Array(info)
            for Cs in 1:length(h_info)
                @test h_info[Cs] == 0
            end
            pivot, info, d_C = CuArrays.CUBLAS.getri_batched(d_A, pivot)
            h_info = Array(info)
            for Cs in 1:length(d_C)
                C   = inv(A[Cs])
                h_C = Array(d_C[Cs])
                @test h_info[Cs] == 0
                @test C ≈ h_C rtol=1e-2
            end
        end

        @testset "matinv_batched" begin
            # generate matrices
            A = [rand(elty,m,m) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            info, d_C = CuArrays.CUBLAS.matinv_batched(d_A)
            for Cs in 1:length(d_C)
                C   = inv(A[Cs])
                h_C = Array(d_C[Cs])
                @test C ≈ h_C
            end
        end

        @testset "geqrf_batched!" begin
            # generate matrices
            A = [rand(elty,m,n) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            tau, d_A = CuArrays.CUBLAS.geqrf_batched!(d_A)
            for As in 1:length(d_A)
                C   = qr(A[As])
                h_A = Array(d_A[As])
                h_tau = Array(tau[As])
                # build up Q
                Q = Matrix(one(elty)*I, min(m,n), min(m,n))
                for i in 1:min(m,n)
                    v = zeros(elty,m)
                    v[i] = one(elty)
                    v[i+1:m] = h_A[i+1:m,i]
                    Q *= I - h_tau[i] * v * v'
                end
                @test Q ≈ Array(C.Q) rtol=1e-2
            end
        end

        @testset "geqrf_batched" begin
            # generate matrices
            A = [rand(elty,m,n) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
            end
            tau, d_B = CuArrays.CUBLAS.geqrf_batched!(d_A)
            for Bs in 1:length(d_B)
                C   = qr(A[Bs])
                h_B = Array(d_B[Bs])
                h_tau = Array(tau[Bs])
                # build up Q
                Q = Matrix(one(elty)*I, min(m,n), min(m,n))
                for i in 1:min(m,n)
                    v = zeros(elty,m)
                    v[i] = one(elty)
                    v[i+1:m] = h_B[i+1:m,i]
                    Q *= I - h_tau[i] * v * v'
                end
                @test Q ≈ Array(C.Q) rtol=1e-2
            end
        end

        @testset "gels_batched!" begin
            # generate matrices
            A = [rand(elty,n,n) for i in 1:10]
            C = [rand(elty,n,k) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            d_C = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
                push!(d_C,CuArray(C[i]))
            end
            d_A, d_C, info = CuArrays.CUBLAS.gels_batched!('N',d_A, d_C)
            for Cs in 1:length(d_C)
                X = A[Cs]\C[Cs]
                h_C = Array(d_C[Cs])
                @test X ≈ h_C rtol=1e-2
            end
        end

        @testset "gels_batched" begin
            # generate matrices
            A = [rand(elty,n,n) for i in 1:10]
            C = [rand(elty,n,k) for i in 1:10]
            # move to device
            d_A = CuArray{elty, 2}[]
            d_C = CuArray{elty, 2}[]
            for i in 1:length(A)
                push!(d_A,CuArray(A[i]))
                push!(d_C,CuArray(C[i]))
            end
            d_B, d_D, info = CuArrays.CUBLAS.gels_batched('N',d_A, d_C)
            for Ds in 1:length(d_D)
                X = A[Ds]\C[Ds]
                h_D = Array(d_D[Ds])
                @test X ≈ h_D rtol=1e-2
            end
        end
        # generate matrices
        A = rand(elty,m,n)
        C = rand(elty,m,n)
        x = rand(elty,m)
        # move to device
        d_A = CuArray(A)
        d_C = CuArray(C)
        d_x = CuArray(x)
        C = diagm(0 => x) * A
        @testset "dgmm!" begin
            # compute
            CuArrays.CUBLAS.dgmm!('L', d_A, d_x, d_C)
            # move to host and compare
            h_C = Array(d_C)
            @test C ≈ h_C
            # bounds checking
            @test_throws DimensionMismatch CuArrays.CUBLAS.dgmm!('R', d_A, d_x, d_C)
            E = rand(elty,m,m)
            d_E = CuArray(E)
            @test_throws DimensionMismatch CuArrays.CUBLAS.dgmm!('L', d_E, d_x, d_C)
        end
        @testset "dgmm" begin
            d_C = CuArrays.CUBLAS.dgmm('L', d_A, d_x)
            # move to host and compare
            h_C = Array(d_C)
            @test C ≈ h_C
        end
    end # extensions
end # elty

end # cublas testset
