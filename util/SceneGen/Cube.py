mid = (0.0, 0.0, 0.0)
stride = 0.6
r = 0.45

t = 2

output = []

for k in range(-t, t + 1):
    for i in range(-t, t + 1):
        for j in range(-t, t + 1):
                output.append("{" + "XMFLOAT3({:.2f}f, {:.2f}f, {:.2f}f), {:.2f}f ".format(
                    mid[0] + i * stride,
                    mid[1] + j * stride,
                    mid[2] + k * stride,
                    r
                    ) + "},")


for s in output:
    print(s)

