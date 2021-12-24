import random

mid = (0.0, 2.0, 0.0)

scope = 3
r_max = 0.5
r_min = 0.2

num = 25
for i in range(num):
    print("{" + "XMFLOAT3({:.2f}f, {:.2f}f, {:.2f}f), {:.2f}f ".format(
        (random.random() - 0.5) * scope,
        (random.random() - 0.5) * scope,
        (random.random() - 0.5) * scope,
        random.random() * (r_max - r_min) + r_min
        ) + "},")